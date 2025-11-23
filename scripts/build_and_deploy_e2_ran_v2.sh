#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# FINAL BUILD + DEPLOY SCRIPT FOR OAI RAN (E2 ENABLED)
# Compatible with openairinterface5g (develop branch)
# Builds:
#   - ran-base:latest
#   - ran-build:latest  (with E2 support)
#   - oai-cu-cp:e2       (from gNB)
#   - oai-du:e2          (from gNB)
#   - oai-cu-up:e2       (from nr-cuup)
#   - oai-nr-ue:e2       (from nrUE)
# Deploys:
#   - Automatic Helm upgrade in namespace oai5g-split
###############################################################################

LAB_ROOT="$HOME/lab"
BUILD_DIR="${LAB_ROOT}/oai-e2-ran"
REPO_DIR="${BUILD_DIR}/openairinterface5g"
REPO_URL="https://github.com/OPENAIRINTERFACE/openairinterface5g.git"
BRANCH="develop"

NAMESPACE="oai5g-split"
HELM_DIR="${LAB_ROOT}/5g-Lab-gnb-split/oai-cn5g-fed"

# RAN Helm releases (from your pod names)
CUCP_RELEASE="oai-cu-cp"
CUUP_RELEASE="oai-cu-up"
DU_RELEASE="oai-du"
UE_RELEASE="oai-nr-ue"

# FINAL IMAGE NAMES
GNB_IMAGE="oai-gnb:e2"
CUUP_IMAGE="oai-cu-up:e2"
UE_IMAGE="oai-nr-ue:e2"
DU_IMAGE="oai-du:e2"

# OAI BUILD OPTIONS
BUILD_OPTION="--gNB --nrUE --build-e2 --ninja"

###############################################################################
echo "=== [0] CHECK ENVIRONMENT ==="
for cmd in docker minikube kubectl helm git; do
  command -v $cmd >/dev/null || { echo "❌ Missing: $cmd" ; exit 1; }
done

kubectl cluster-info >/dev/null || {
  echo "❌ kubectl cannot connect to cluster."
  exit 1
}

###############################################################################
echo "=== [1] PREPARE REPO ==="
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "→ Cloning OAI repo..."
  git clone -b "$BRANCH" "$REPO_URL"
else
  echo "→ Updating existing repo..."
  cd "$REPO_DIR"
  git fetch
  git checkout "$BRANCH"
  git pull --rebase
fi

cd "$REPO_DIR"
echo "Repository: $(pwd)"

###############################################################################
echo "=== [2] BUILD ran-base ==="
docker build \
  --target ran-base \
  --tag ran-base:latest \
  --file docker/Dockerfile.base.ubuntu .

###############################################################################
echo "=== [3] BUILD ran-build (with E2 support) ==="
docker build \
  --target ran-build \
  --tag ran-build:latest \
  --file docker/Dockerfile.build.ubuntu \
  --build-arg "BUILD_OPTION=${BUILD_OPTION}" .

###############################################################################
echo "=== [4] BUILD CU-CP (oai-gnb -> cu-cp) ==="
docker build \
  --target oai-gnb \
  --tag "$GNB_IMAGE" \
  --file docker/Dockerfile.gNB.ubuntu .

echo "=== [5] BUILD DU (oai-gnb -> du) ==="
docker build \
  --target oai-gnb \
  --tag "$DU_IMAGE" \
  --file docker/Dockerfile.gNB.ubuntu .

###############################################################################
echo "=== [6] BUILD CU-UP ==="
docker build \
  --target oai-nr-cuup \
  --tag "$CUUP_IMAGE" \
  --file docker/Dockerfile.nr-cuup.ubuntu .

###############################################################################
echo "=== [7] BUILD NR-UE ==="
docker build \
  --target oai-nr-ue \
  --tag "$UE_IMAGE" \
  --file docker/Dockerfile.nrUE.ubuntu .

###############################################################################
echo "=== [8] LOAD IMAGES TO MINIKUBE ==="
minikube image load "$GNB_IMAGE"
minikube image load "$DU_IMAGE"
minikube image load "$CUUP_IMAGE"
minikube image load "$UE_IMAGE"

###############################################################################
echo "=== [9] HELM UPGRADE RAN DEPLOYMENTS ==="

cd "$HELM_DIR"

echo "→ Upgrade CU-CP with ${GNB_IMAGE}"
helm upgrade "$CUCP_RELEASE" charts/oai-5g-ran/oai-cu-cp \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-gnb" \
  --set image.tag="e2"

echo "→ Upgrade DU with ${DU_IMAGE}"
helm upgrade "$DU_RELEASE" charts/oai-5g-ran/oai-du \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-du" \
  --set image.tag="e2"

echo "→ Upgrade CU-UP with ${CUUP_IMAGE}"
helm upgrade "$CUUP_RELEASE" charts/oai-5g-ran/oai-cu-up \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-cu-up" \
  --set image.tag="e2"

echo "→ Upgrade NR-UE with ${UE_IMAGE}"
helm upgrade "$UE_RELEASE" charts/oai-5g-ran/oai-nr-ue \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-nr-ue" \
  --set image.tag="e2"

###############################################################################
echo "=== [10] WAIT FOR RAN ROLLOUT ==="

kubectl rollout status deployment/"$CUCP_RELEASE" -n "$NAMESPACE" --timeout=600s || true
kubectl rollout status deployment/"$DU_RELEASE"   -n "$NAMESPACE" --timeout=600s || true
kubectl rollout status deployment/"$CUUP_RELEASE" -n "$NAMESPACE" --timeout=600s || true
kubectl rollout status deployment/"$UE_RELEASE"   -n "$NAMESPACE" --timeout=600s || true

###############################################################################
echo "=== DONE ==="
echo "✔ E2 RAN images built and deployed."
echo "✔ Active RAN pods:"
kubectl get pods -n "$NAMESPACE" -o wide | grep -E 'cu|du|nr-ue|NAME'
echo
echo "Next step:"
echo " - Add E2 configuration sections in gNB (CU-CP/DU) .conf"
echo " - Point to RIC E2TERM service (port 36421)"
echo " - Then check logs with:"
echo "     kubectl logs -n $NAMESPACE deployment/$CUCP_RELEASE | grep -i e2"
echo "==================================================================="
