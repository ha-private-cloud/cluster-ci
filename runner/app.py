import os
import re
import uuid

from flask import Flask, Response, jsonify, request, stream_with_context
from kubernetes import config as k8s_config

from auth import require_token
from buildqueue import BuildQueue
from jobs import JobRunner
from storage import save_upload

APP_NAME_RE = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")
TAG_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$")


def create_app() -> Flask:
    app = Flask(__name__)

    k8s_config.load_incluster_config()

    job_runner = JobRunner(
        namespace=os.environ["NAMESPACE"],
        kaniko_image=os.environ["KANIKO_IMAGE"],
        nexus_hostname=os.environ["NEXUS_DOCKER_HOSTNAME"],
        nexus_credentials_secret=os.environ["NEXUS_CREDENTIALS_SECRET"],
        workspace_pvc=os.environ["WORKSPACE_PVC"],
        build_service_account=os.environ["BUILD_SERVICE_ACCOUNT"],
        job_ttl_seconds=int(os.environ["BUILD_JOB_TTL_SECONDS"]),
    )
    build_queue = BuildQueue(job_runner, max_concurrent=int(os.environ["MAX_CONCURRENT_BUILDS"]))
    build_queue.start()

    @app.get("/healthz")
    def healthz():
        return {"status": "ok"}

    @app.post("/builds")
    @require_token
    def create_build():
        app_name = request.form.get("app", "")
        tag = request.form.get("tag", "")
        namespace = request.form.get("namespace", "")
        source = request.files.get("source")

        if not APP_NAME_RE.match(app_name):
            return jsonify({"error": "app must be a valid k8s name (lowercase alphanumeric/hyphens)"}), 400
        if not APP_NAME_RE.match(namespace):
            return jsonify({"error": "namespace must be a valid k8s name (lowercase alphanumeric/hyphens)"}), 400
        if not TAG_RE.match(tag):
            return jsonify({"error": "invalid tag"}), 400
        if source is None:
            return jsonify({"error": "source (tar.gz) is required"}), 400

        build_id = uuid.uuid4().hex[:12]
        save_upload(build_id, source)
        build = build_queue.submit(build_id=build_id, app_name=app_name, tag=tag, namespace=namespace)
        return jsonify(build.to_dict()), 202

    @app.get("/builds/<build_id>")
    @require_token
    def get_build(build_id):
        build = build_queue.get(build_id)
        if build is None:
            return jsonify({"error": "not found"}), 404
        return jsonify(build.to_dict())

    @app.get("/builds/<build_id>/logs")
    @require_token
    def stream_logs(build_id):
        build = build_queue.get(build_id)
        if build is None:
            return jsonify({"error": "not found"}), 404

        def generate():
            for line in job_runner.tail_logs(build):
                yield f"data: {line}\n\n"
            yield f"event: done\ndata: {build.status}\n\n"

        return Response(stream_with_context(generate()), mimetype="text/event-stream")

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
