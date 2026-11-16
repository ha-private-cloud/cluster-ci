# cluster-ci

The build service inside the cluster. cluster-cli uploads an app's source here, and it runs the tests and builds and pushes the image to the Nexus registry. It never deploys anything. Deploying is done afterwards by the app's own OpenTofu.

## How a build runs

The runner is a small Flask app in the `ci` namespace, at ci.clusterkeep.dev.net. Each build becomes one Kubernetes Job with two steps:

1. The tests run with `uv sync --locked && uv run pytest`. If they fail, nothing is built.
2. Kaniko builds the image from the app's Dockerfile and pushes it to registry.clusterkeep.dev.net with the requested tag.

Builds run one at a time by default, and finished Jobs are cleaned up after an hour. A ResourceQuota keeps builds from taking over the cluster.

## Runner endpoints

Every endpoint apart from `/healthz` needs the runner's API token as a bearer token.

| Method | Path | What it does |
|---|---|---|
| GET | `/healthz` | Kubernetes health check |
| POST | `/builds` | Queue a build. Takes the app name, tag, namespace and the source as a `.tar.gz` |
| GET | `/builds/<build_id>` | A build's status |
| GET | `/builds/<build_id>/logs` | A build's test and build output |

## Working on the runner

The runner lives in `runner/`, with its own `pyproject.toml` and Dockerfile. To run it locally:

```sh
cd runner
uv sync
uv run flask --app app run --debug
```

It needs a kubeconfig or an in-cluster service account to submit Jobs, so it's only really useful inside the `ci` namespace.

It runs as a single gunicorn worker with eight threads. The build queue and build statuses are kept in memory, so a second worker would have its own separate copy of both.

## Technologies

- Python and Flask for the runner, talking to Kubernetes with the official client
- Kaniko for building images without a Docker daemon or a privileged pod
- uv and pytest inside the build Job
- OpenTofu for the namespace, RBAC, quota, token and runner Deployment

## Releasing

Pushing a `vX.Y.Z` tag runs the deploy workflow on the CI bastion:

1. `rebuild-runner.sh` builds the runner image from that tag's `runner/` folder with Podman and pushes it as `ci-runner:vX.Y.Z`. The runner can't build its own image, so this happens on the bastion instead.
2. The shared `pipelines` workflow plans the OpenTofu config with `runner_image_tag` set to the same tag.

Running the deploy workflow by hand with the tag applies it. The runner version always matches the release, so a later apply can't roll it back. Only tags pushed since this change have a runner image, so apply one of those.

The script reads the CI push credentials from the cluster each time and deletes its copy afterwards. To build an image by hand on the bastion:

```sh
rebuild-runner.sh v0.2.0
```

## First-time setup

1. Create a push user in Nexus for CI, and put its username and password in the tfvars on the CI bastion.
2. Push a release tag to build the first runner image, then apply it with the deploy workflow.
3. Put the runner token in cluster-cli's config:

   ```sh
   cluster-cli tofu cluster-ci output -raw runner_api_token
   ```
