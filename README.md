# cluster-ci

In-cluster build/test/push/deploy pipeline for apps in this project (starting
with `clusterkeep-ui`). A Flask "runner" (`runner/`) submits Kubernetes Jobs
that run `pytest`, build+push an image with Kaniko, then `helm upgrade` the
target app — see `../ci-cli` for the CLI that talks to it.

## Prerequisites (one-time, do these before `tofu apply` here)

1. **CoreDNS fix in `cluster-config`** — already applied as part of this
   work; `registry.talos.lab` needs to resolve in-cluster or Kaniko's push
   step NXDOMAINs. If this repo is ever rebuilt from scratch, re-check
   `../cluster-config/coredns.tf`'s hosts block includes
   `var.nexus_docker_hostname`.
2. **Create a dedicated Nexus push user.** Not Terraform-managed: Nexus's
   user-creation REST endpoint isn't idempotent (unlike, say,
   `cluster-auth/users.tf`'s recovery-link POST, which is safe to re-run), so
   automating it would break every `tofu plan` after the first apply — same
   reasoning `cluster-config` already uses for not managing the docker-hosted
   repo/realm setup.

   Get the admin password and log in:
   ```sh
   kubectl exec -n nexus deploy/nexus -- cat /nexus-data/admin.password
   ```
   Open `https://nexus.talos.lab`, log in as `admin`, then **Security → Users
   → Create Local User** — username `ci`, grant a role with
   `nx-repository-view-docker-docker-hosted-*` (add/edit/read/delete on the
   docker-hosted repo). Put the resulting username/password in this repo's
   `terraform.tfvars` (gitignored, same convention as `clusterkeep-ui`'s
   `registry_username`/`registry_password`):
   ```
   nexus_ci_username = "ci"
   nexus_ci_password = "<password you set>"
   runner_image_tag  = "v0.1.0"
   ```
3. **Build and push the runner's own bootstrap image.** The pipeline can't
   build the thing that runs the pipeline — from a machine with Docker:
   ```sh
   cd runner
   docker build -t registry.talos.lab/ci-runner:v0.1.0 .
   docker push registry.talos.lab/ci-runner:v0.1.0
   ```
   (Nexus's docker-hosted repo needs `docker login registry.talos.lab` first,
   using the same `ci` user credentials above, or the `admin` account.)

## Apply

```sh
tofu init
tofu plan
tofu apply
```

Creates: namespace `ci`, RBAC (runner's own Job-management Role, the
`ci-build`/`ci-deploy` ServiceAccounts, the `ci-deploy` ClusterRole app repos
bind against), a shared `ReadWriteMany` PVC on `nfs-csi` for build workspaces,
a `ResourceQuota`, the Nexus push-credentials Secret, the runner's API
bearer-token Secret, and the runner Deployment/Service/Ingress itself (needs
step 3 above done first, or the Deployment will sit in `ImagePullBackOff`
and `tofu apply` will time out waiting for its rollout).

## After applying

```sh
tofu output -raw runner_api_token
```

Put it in `~/.config/ci-cli/config.toml` (see `../ci-cli/README.md`). Add
`ci.talos.lab` to `/etc/hosts`, pointing at a worker node IP.

## Per-app setup

Each app repo needs its own `RoleBinding` granting `ci-deploy`'s ClusterRole
(output as `deploy_cluster_role_name`) to the `ci-deploy` ServiceAccount
(output as `deploy_service_account`), scoped to that app's own namespace —
see `../clusterkeep-ui/ci-rbac.tf` for the first example. This is
deliberately each app repo's own responsibility, not centralized here, same
convention `cluster-rbac` established for "who can touch this namespace."

The deploy Job's `helm upgrade --namespace <target>` uses whatever
`namespace` the caller passes to `POST /builds` (or `ci-cli build
--namespace ...`) — it is **not** derived from the app name. If a caller
passes a namespace with no matching `RoleBinding`, the deploy Job fails
cleanly (Kubernetes RBAC denies the `helm upgrade`) rather than deploying
somewhere unintended.

The app's Helm chart must live at `charts/<app-name>/` inside the app repo
(not published to Nexus's Helm-hosted repo type — not set up, and not worth
it for a single app) — `ci-cli` uploads the whole app directory, chart
included, and the deploy Job's `helm upgrade` reads it from there.

## Known tradeoffs

- **Deploys go through `helm upgrade --reuse-values`, not `tofu apply`.**
  Avoids migrating any app repo's local Terraform state to a remote backend
  (a much bigger, riskier lift). Cost: a routine `tofu apply` in an app repo
  after a pipeline deploy will roll `image.tag` back to whatever's in that
  repo's `terraform.tfvars` unless updated first.
- **Builds are serialized** (`max_concurrent_builds = 1`). Worker node
  `talos-c94-oxe` (192.168.0.16) already runs Nexus and sits close to its
  memory limit ceiling — concurrent builds would make that worse, and this
  is a single-user homelab where nothing needs parallel builds.
- **Runner auth is a static bearer token**, not OIDC through the existing
  Authentik instance (`cluster-auth`). Authentik is wired for browser
  redirect flows only today; a single trusted CLI caller on the LAN doesn't
  need more than a token in a `0600` config file.
