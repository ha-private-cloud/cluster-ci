# cluster-ci

In-cluster build/test/push pipeline for apps in this project (starting with
`clusterkeep-ui`). A Flask "runner" (`runner/`) submits a Kubernetes Job that
runs `pytest`, then builds+pushes an image with Kaniko , see `../cluster-cli`
for the CLI that talks to it. Deploying (running `helm upgrade` against the
app's chart) happens client-side, via `cluster-cli`, after a build succeeds ,
this pipeline only builds and pushes, it never touches the cluster API to
deploy anything.

## Prerequisites (one-time, do these before `tofu apply` here)

1. **CoreDNS fix in `cluster-config`**
2. **Create a dedicated Nexus push user.** 
3. **Build and push the runner's own bootstrap image.**:
   ```sh
   cd runner
   docker build -t registry.talos.lab/ci-runner:v0.1.0 .
   docker push registry.talos.lab/ci-runner:v0.1.0
   ```

## Apply

All `.tf` files live under `tofu/`, not the repo root:

```sh
cd tofu
tofu init
tofu plan
tofu apply
```

## After applying

```sh
tofu output -raw runner_api_token
```

Put it in `~/.config/cluster-cli/config.toml`.
Add `ci.talos.lab` to `/etc/hosts`, pointing at a worker node IP.
