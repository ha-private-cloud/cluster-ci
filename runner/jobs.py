import shutil
import time
from pathlib import Path

from kubernetes import client, watch


class JobRunner:
    """Runs each build as a single Kubernetes Job (test + Kaniko build/push),
    under a ServiceAccount with zero cluster API access , Kaniko only needs
    registry credentials, not anything Kubernetes-shaped. Deploying (running
    `helm upgrade` against the chart at ~/project/charts/<app>) happens
    client-side afterward, via `cluster-cli deploy`/`build` , not here."""

    def __init__(
        self,
        *,
        namespace: str,
        kaniko_image: str,
        nexus_hostname: str,
        nexus_credentials_secret: str,
        workspace_pvc: str,
        build_service_account: str,
        job_ttl_seconds: int,
    ):
        self.namespace = namespace
        self.kaniko_image = kaniko_image
        self.nexus_hostname = nexus_hostname
        self.nexus_credentials_secret = nexus_credentials_secret
        self.workspace_pvc = workspace_pvc
        self.build_service_account = build_service_account
        self.job_ttl_seconds = job_ttl_seconds
        self.batch = client.BatchV1Api()
        self.core = client.CoreV1Api()

    def run_pipeline(self, build) -> None:
        build.stage = "testing"
        build.build_job_name = f"build-{build.app_name}-{build.id}"
        self._submit_build_job(build)
        build.status = "succeeded" if self._wait_for_job(build.build_job_name, build) else "failed"

    def _submit_build_job(self, build) -> None:
        workspace_path = f"/workspace/{build.id}"
        manifest = {
            "apiVersion": "batch/v1",
            "kind": "Job",
            "metadata": {
                "name": build.build_job_name,
                "namespace": self.namespace,
                "labels": {"build-id": build.id, "role": "build"},
            },
            "spec": {
                "backoffLimit": 0,
                "ttlSecondsAfterFinished": self.job_ttl_seconds,
                "template": {
                    "metadata": {"labels": {"build-id": build.id, "role": "build"}},
                    "spec": {
                        "serviceAccountName": self.build_service_account,
                        "restartPolicy": "Never",
                        "initContainers": [
                            {
                                "name": "test",
                                "image": "ghcr.io/astral-sh/uv:python3.13-bookworm-slim",
                                "workingDir": workspace_path,
                                "command": ["sh", "-c", "uv sync --locked && uv run pytest"],
                                "volumeMounts": [{"name": "workspace", "mountPath": "/workspace"}],
                                "resources": {
                                    "requests": {"cpu": "250m", "memory": "256Mi"},
                                    "limits": {"cpu": "500m", "memory": "512Mi"},
                                },
                            }
                        ],
                        "containers": [
                            {
                                "name": "build-push",
                                "image": self.kaniko_image,
                                "args": [
                                    f"--context=dir://{workspace_path}",
                                    f"--destination={self.nexus_hostname}/{build.app_name}:{build.tag}",
                                    f"--destination={self.nexus_hostname}/{build.app_name}:latest",
                                    # Self-signed cert on the ingress-nginx side of registry.talos.lab ,
                                    # same "accept self-signed on the LAN" pattern used elsewhere.
                                    "--skip-tls-verify",
                                ],
                                "volumeMounts": [
                                    {"name": "workspace", "mountPath": "/workspace"},
                                    {"name": "docker-config", "mountPath": "/kaniko/.docker"},
                                ],
                                "resources": {
                                    "requests": {"cpu": "500m", "memory": "512Mi"},
                                    "limits": {"cpu": "1", "memory": "1Gi"},
                                },
                            }
                        ],
                        "volumes": [
                            {"name": "workspace", "persistentVolumeClaim": {"claimName": self.workspace_pvc}},
                            {
                                "name": "docker-config",
                                "secret": {
                                    "secretName": self.nexus_credentials_secret,
                                    # Kaniko needs the file literally named config.json under
                                    # /kaniko/.docker; the Secret stores it as .dockerconfigjson.
                                    "items": [{"key": ".dockerconfigjson", "path": "config.json"}],
                                },
                            },
                        ],
                        # Steer builds away from talos-c94-oxe, which already runs Nexus and
                        # sits close to its memory limit ceiling.
                        "affinity": {
                            "podAntiAffinity": {
                                "preferredDuringSchedulingIgnoredDuringExecution": [
                                    {
                                        "weight": 100,
                                        "podAffinityTerm": {
                                            "labelSelector": {
                                                "matchExpressions": [
                                                    {
                                                        "key": "app.kubernetes.io/name",
                                                        "operator": "In",
                                                        "values": ["nexus"],
                                                    }
                                                ]
                                            },
                                            "topologyKey": "kubernetes.io/hostname",
                                        },
                                    }
                                ]
                            }
                        },
                    },
                },
            },
        }
        self.batch.create_namespaced_job(self.namespace, manifest)

    def _wait_for_job(self, job_name: str, build, poll_interval: float = 2.0, timeout: float = 900.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            job = self.batch.read_namespaced_job_status(job_name, self.namespace)
            if job.status.succeeded:
                return True
            if job.status.failed:
                build.error = self._failure_reason(job_name)
                return False
            time.sleep(poll_interval)
        build.error = f"timed out waiting for {job_name}"
        return False

    def _failure_reason(self, job_name: str) -> str:
        pods = self.core.list_namespaced_pod(self.namespace, label_selector=f"job-name={job_name}")
        for pod in pods.items:
            statuses = list(pod.status.init_container_statuses or []) + list(pod.status.container_statuses or [])
            for status in statuses:
                terminated = status.state.terminated
                if terminated and terminated.exit_code:
                    return f"{status.name} exited {terminated.exit_code}: {terminated.reason}"
        return "job failed"

    def tail_logs(self, build):
        """Yields log lines across the build Job's pod/containers in order, for the SSE endpoint."""
        if build.build_job_name is None:
            return
        pod_name = self._wait_for_pod(build.build_job_name)
        if pod_name is None:
            return
        for container in ["test", "build-push"]:
            yield from self._stream_container_logs(pod_name, container)

    def _wait_for_pod(self, job_name: str, timeout: float = 60.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            pods = self.core.list_namespaced_pod(self.namespace, label_selector=f"job-name={job_name}")
            if pods.items:
                return pods.items[0].metadata.name
            time.sleep(1)
        return None

    def _stream_container_logs(self, pod_name: str, container: str):
        w = watch.Watch()
        try:
            for line in w.stream(
                self.core.read_namespaced_pod_log,
                name=pod_name,
                namespace=self.namespace,
                container=container,
            ):
                yield line
        except client.exceptions.ApiException:
            return

    def cleanup(self, build) -> None:
        shutil.rmtree(Path("/workspace") / build.id, ignore_errors=True)
