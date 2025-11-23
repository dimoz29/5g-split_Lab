#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Build custom CU-CP image (oai-gnb:2024.w32-flexric) with FlexRIC SM libs
# and patch the oai-cu-cp deployment to use it.
#
# Assumptions:
#   - Dockerfile.oai-gnb-flexric is in:  $HOME/lab/5g-Lab-gnb-split/
#   - Namespace: oai5g-split
#   - CU-CP deployment: oai-cu-cp
#   - CU-CP container name: oaicucp
###############################################################################

LAB_ROOT="$HOME/lab"
LAB_DIR="${LAB_ROOT}/5g-Lab-gnb-split"
NAMESPACE="oai5g-split"
CUCP_DEPLOY="oai-cu-cp"
CUCP_CONTAINER="oaicucp"
CUSTOM_IMAGE="oai-gnb:2024.w32-flexric"
DOCKERFILE="${LAB_DIR}/Dockerfile.oai-gnb-flexric"

echo "=== [0] Environment checks ==="
for cmd in docker minikube kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "❌ Missing command: $cmd"
    exit 1
  }
done

kubectl cluster-info >/dev/null 2>&1 || {
  echo "❌ kubectl cannot reach Kubernetes cluster (check minikube)."
  exit 1
}

if [ ! -f "$DOCKERFILE" ]; then
  echo "❌ Dockerfile not found: $DOCKERFILE"
  echo "   Expected Dockerfile.oai-gnb-flexric in $LAB_DIR"
  exit 1
fi

if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  echo "❌ Namespace $NAMESPACE does not exist. Run deploy_all_split_lab.sh first."
  exit 1
fi

if ! kubectl -n "$NAMESPACE" get deploy "$CUCP_DEPLOY" >/dev/null 2>&1; then
  echo "❌ Deployment $CUCP_DEPLOY not found in namespace $NAMESPACE."
  echo "   Make sure the split RAN is deployed."
  exit 1
fi

echo "=== [1] Build custom CU-CP image with FlexRIC SMs ==="
cd "$LAB_DIR"

echo "→ Building image: $CUSTOM_IMAGE"
docker build \
  -t "$CUSTOM_IMAGE" \
  -f "$DOCKERFILE" .

echo "=== [2] Load custom image into Minikube ==="
minikube image load "$CUSTOM_IMAGE"

echo "=== [3] Patch oai-cu-cp deployment to use $CUSTOM_IMAGE ==="
kubectl set image deployment/"$CUCP_DEPLOY" -n "$NAMESPACE" \
  "$CUCP_CONTAINER"="$CUSTOM_IMAGE"

echo "→ Waiting for rollout..."
kubectl rollout status deployment/"$CUCP_DEPLOY" -n "$NAMESPACE" --timeout=600s || true

echo "=== [4] Verify CU-CP pod & SM libs ==="
kubectl get pods -n "$NAMESPACE" | grep oai-cu-cp || true

CUCP_POD="$(
  kubectl get pods -n "$NAMESPACE" -o name | grep oai-cu-cp | head -1
)"

if [ -n "$CUCP_POD" ]; then
  echo "→ Checking SM libraries inside CU-CP (ls /usr/local/lib/flexric)"
  kubectl exec -n "$NAMESPACE" "$CUCP_POD" -- \
    ls -1 /usr/local/lib/flexric || echo "⚠️ Could not list SM libs."
fi

echo
echo "=================================================================="
echo "✔ Custom CU-CP image $CUSTOM_IMAGE built and deployed."
echo "✔ Deployment: $CUCP_DEPLOY uses container image $CUSTOM_IMAGE"
echo "=================================================================="
