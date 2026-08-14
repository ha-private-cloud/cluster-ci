#!/usr/bin/env bash
# Rebuilds and redeploys the ci-runner image.
#
# Requires:
#   - podman
#   - ~/.config/containers/auth.json with push creds for registry.talos.lab,
#   - KUBECONFIG pointing at the cluster
#
# Usage:
#   rebuild-runner.sh v0.1.5

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <version-tag>  (e.g. v0.1.5)" >&2
  exit 1
fi

VERSION="$1"
RUNNER_DIR="${HOME}/project/cluster-ci/runner"  # fixed path, not relative to this script , see sync-repos.sh
IMAGE="registry.talos.lab/ci-runner:${VERSION}"

echo "==> Building ${IMAGE}"
podman build -t "${IMAGE}" "${RUNNER_DIR}"

echo "==> Pushing ${IMAGE}"
podman push --tls-verify=false "${IMAGE}"

echo "==> Updating the ci-runner Deployment"
kubectl set image deployment/ci-runner "runner=${IMAGE}" -n ci
kubectl rollout status deployment/ci-runner -n ci --timeout=120s

echo "==> Done , ${IMAGE} is live. Verify:"
echo "      kubectl get pods -n ci -l app=ci-runner -o jsonpath='{.items[0].spec.containers[0].image}'"
echo "      curl -sk https://ci.talos.lab/healthz"
