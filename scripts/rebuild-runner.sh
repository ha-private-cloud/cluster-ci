#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <release-tag>  (e.g. v0.2.0)" >&2
  exit 1
fi

TAG="$1"
REPO="${HOME}/project/cluster-ci"
REGISTRY="${REGISTRY:-registry.clusterkeep.dev.net}"
IMAGE="${REGISTRY}/ci-runner:${TAG}"
KUBECONFIG="${KUBECONFIG:-${HOME}/project/proxmox-tofu/_out/kubeconfig}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

if [ ! -w "${XDG_RUNTIME_DIR}" ]; then
  echo "${XDG_RUNTIME_DIR} isn't writable. Run 'sudo loginctl enable-linger $(id -un)' once on this machine." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
chmod 700 "${WORK}"

echo "==> Taking runner/ from ${TAG}"
git -C "${REPO}" fetch --quiet --tags --force origin
git -C "${REPO}" archive "${TAG}" runner | tar -x -C "${WORK}"

echo "==> Reading the CI push credentials from the cluster"
kubectl --kubeconfig "${KUBECONFIG}" get secret nexus-ci-push-credentials -n ci \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > "${WORK}/auth.json"

echo "==> Building ${IMAGE}"
podman build -t "${IMAGE}" "${WORK}/runner"

echo "==> Pushing ${IMAGE}"
podman push --authfile "${WORK}/auth.json" --tls-verify=false "${IMAGE}"

echo "==> ${IMAGE} pushed. Apply cluster-ci with runner_image_tag=${TAG} to deploy it."
