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
3. **Build and push the runner's own bootstrap image**, from the bastion (see "Rebuilding the runner" below):
   ```sh
   ./scripts/rebuild-runner.sh v0.1.0
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

## Rebuilding the runner

`cluster-ci` builds every other app's image , but not its own (nothing can build the thing that runs the build pipeline). Whenever `runner/` changes, rebuild and redeploy it from the bastion:

```sh
./scripts/rebuild-runner.sh v0.1.5
```

Builds with `podman` directly against `registry.talos.lab` (rather than an in-cluster Kaniko Job , the bastion has no Pod Security Admission restrictions to route around in the first place), then updates the `ci-runner` Deployment and waits for rollout. Needs `~/.config/containers/auth.json` with push credentials , reuse the cluster's own Nexus push secret rather than creating a new one:

```sh
kubectl get secret nexus-ci-push-credentials -n ci -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > ~/.config/containers/auth.json
```

Bump the version each time (`tofu/variables.tf`'s `runner_image_tag` default has no fallback , the script doesn't update Tofu state, so if you later run `tofu apply` here, pass `-var runner_image_tag=<version>` or it'll fall back to whatever's in your `terraform.tfvars`).
