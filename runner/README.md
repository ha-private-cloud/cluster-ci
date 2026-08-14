# ci-runner

The in-cluster half of the build pipeline (see `../README.md` for the full
picture). Flask API that `cluster-cli` talks to; submits a build-push Job
(pytest + Kaniko) per build, streaming logs back over SSE. Deploying
happens client-side in `cluster-cli` after a build succeeds , this service
never runs `helm` or touches the cluster API beyond managing its own Jobs.

## Local development

```sh
uv sync
uv run flask --app app run --debug
```

(Needs a valid kubeconfig / in-cluster context to actually submit Jobs , this
is really only meant to run inside the `ci` namespace.)

## Container image

```sh
docker build -t registry.talos.lab/ci-runner:<tag> .
docker push registry.talos.lab/ci-runner:<tag>
```

Single gunicorn worker process, multiple threads (`--workers 1 --threads 8`)
deliberately , the build queue and in-memory build-status map live in
process memory, so a second worker process would maintain its own,
disconnected copy of both.
