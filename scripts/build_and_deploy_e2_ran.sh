#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Build + Deploy OAI RAN with E2 support (CU-CP / CU-UP / DU / NR-UE)
# - Χτίζει E2-enabled Docker images από openairinterface5g/docker
# - Φορτώνει τις images στο Minikube
# - Κάνει helm upgrade στα υπάρχοντα RAN releases στο namespace oai5g-split
# - Χρησιμοποιεί --reuse-values για να ΜΗΝ χαλάσει τα υπάρχοντα settings
###############################################################################

# === CONFIG ==================================================================

LAB_ROOT="${HOME}/lab"

# Πού θα βάλουμε το openairinterface5g repo για το build
RAN_BUILD_DIR="${LAB_ROOT}/oai-e2-ran"
OAI_RAN_REPO_URL="https://github.com/OPENAIRINTERFACE/openairinterface5g.git"
OAI_RAN_BRANCH="develop"

# Namespace του split lab (Phase 2)
NAMESPACE="oai5g-split"

# Helm chart repo directory για το OAI CN5G (υπάρχει ήδη από πριν)
CN5G_HELM_DIR="${LAB_ROOT}/5g-Lab-gnb-split/oai-cn5g-fed"

# Helm release names για τα RAN components (όπως φαίνονται στα pod names)
CUCP_RELEASE="oai-cu-cp"
CUUP_RELEASE="oai-cu-up"
DU_RELEASE="oai-du"
UE_RELEASE="oai-nr-ue"

# Docker tags για τις E2-enabled images
CUCP_IMAGE="oai-cu-cp:e2"
CUUP_IMAGE="oai-cu-up:e2"
DU_IMAGE="oai-du:e2"
UE_IMAGE="oai-nr-ue:e2"

# BUILD_OPTION, όπως στο OAI doc (gNB + nrUE + E2 + ninja build)
BUILD_OPTION="--gNB --nrUE --build-e2 --ninja"

# ============================================================================

echo "=== [0] Έλεγχος εργαλείων και cluster ==="

for cmd in docker minikube kubectl helm git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Λείπει το εργαλείο: $cmd"
    exit 1
  fi
done

kubectl cluster-info >/dev/null 2>&1 || {
  echo "❌ kubectl δεν βλέπει cluster. Βεβαιώσου ότι το minikube τρέχει (minikube start)."
  exit 1
}

echo "=== [1] Προετοιμασία φακέλου build: ${RAN_BUILD_DIR} ==="
mkdir -p "${RAN_BUILD_DIR}"
cd "${RAN_BUILD_DIR}"

if [ -d "openairinterface5g/.git" ]; then
  echo "→ Repo openairinterface5g υπάρχει ήδη, κάνω fetch/pull..."
  cd openairinterface5g
  git fetch origin
  git checkout "${OAI_RAN_BRANCH}"
  git pull --rebase
else
  echo "→ Κάνω clone το openairinterface5g (${OAI_RAN_BRANCH})..."
  git clone --branch "${OAI_RAN_BRANCH}" "${OAI_RAN_REPO_URL}"
  cd openairinterface5g
fi

echo "Τρέχον repo: $(pwd)"

echo "=== [2] Build E2-enabled Docker images (CU-CP / CU-UP / DU / NR-UE) ==="
cd docker

echo "→ CU-CP image: ${CUCP_IMAGE}"
docker build \
  -f Dockerfile.cu-cp \
  --build-arg BUILD_OPTION="${BUILD_OPTION}" \
  -t "${CUCP_IMAGE}" \
  .

echo "→ CU-UP image: ${CUUP_IMAGE}"
docker build \
  -f Dockerfile.cu-up \
  --build-arg BUILD_OPTION="${BUILD_OPTION}" \
  -t "${CUUP_IMAGE}" \
  .

echo "→ DU image: ${DU_IMAGE}"
docker build \
  -f Dockerfile.du \
  --build-arg BUILD_OPTION="${BUILD_OPTION}" \
  -t "${DU_IMAGE}" \
  .

echo "→ NR-UE image: ${UE_IMAGE}"
docker build \
  -f Dockerfile.nr-ue \
  --build-arg BUILD_OPTION="${BUILD_OPTION}" \
  -t "${UE_IMAGE}" \
  .

echo "=== [3] Φόρτωση images στο Minikube ==="

minikube image load "${CUCP_IMAGE}"
minikube image load "${CUUP_IMAGE}"
minikube image load "${DU_IMAGE}"
minikube image load "${UE_IMAGE}"

echo "Images loaded into Minikube:"
echo "  ${CUCP_IMAGE}"
echo "  ${CUUP_IMAGE}"
echo "  ${DU_IMAGE}"
echo "  ${UE_IMAGE}"

echo "=== [4] Helm upgrade των RAN releases ώστε να χρησιμοποιούν τις νέες E2 images ==="

if [ ! -d "${CN5G_HELM_DIR}" ]; then
  echo "❌ Δεν βρέθηκε το Helm repo directory: ${CN5G_HELM_DIR}"
  echo "   Βεβαιώσου ότι το oai-cn5g-fed έχει γίνει clone στο ${CN5G_HELM_DIR}"
  exit 1
fi

cd "${CN5G_HELM_DIR}"

echo "→ CU-CP (release: ${CUCP_RELEASE})"
helm upgrade "${CUCP_RELEASE}" charts/oai-5g-ran/oai-cu-cp \
  --namespace "${NAMESPACE}" \
  --reuse-values \
  --set image.repository=oai-cu-cp \
  --set image.tag=e2

echo "→ CU-UP (release: ${CUUP_RELEASE})"
helm upgrade "${CUUP_RELEASE}" charts/oai-5g-ran/oai-cu-up \
  --namespace "${NAMESPACE}" \
  --reuse-values \
  --set image.repository=oai-cu-up \
  --set image.tag=e2

echo "→ DU (release: ${DU_RELEASE})"
helm upgrade "${DU_RELEASE}" charts/oai-5g-ran/oai-du \
  --namespace "${NAMESPACE}" \
  --reuse-values \
  --set image.repository=oai-du \
  --set image.tag=e2

echo "→ NR-UE (release: ${UE_RELEASE})"
helm upgrade "${UE_RELEASE}" charts/oai-5g-ran/oai-nr-ue \
  --namespace "${NAMESPACE}" \
  --reuse-values \
  --set image.repository=oai-nr-ue \
  --set image.tag=e2

echo "=== [5] Περιμένω RAN pods να γίνουν Ready με τις νέες images ==="

kubectl rollout status deployment/"${CUCP_RELEASE}" -n "${NAMESPACE}" --timeout=600s || true
kubectl rollout status deployment/"${CUUP_RELEASE}" -n "${NAMESPACE}" --timeout=600s || true
kubectl rollout status deployment/"${DU_RELEASE}"   -n "${NAMESPACE}" --timeout=600s || true
kubectl rollout status deployment/"${UE_RELEASE}"   -n "${NAMESPACE}" --timeout=600s || true

echo
echo "=== [6] Τρέχουσα κατάσταση RAN pods στο namespace ${NAMESPACE} ==="
kubectl get pods -n "${NAMESPACE}" -o wide | egrep "cu-cp|cu-up|du|nr-ue|NAME"

echo
echo "=================================================================="
echo "✔ Build + deploy E2-enabled RAN ολοκληρώθηκε."
echo
echo "Χρησιμοποιούνται πλέον οι images:"
echo "  ${CUCP_IMAGE}"
echo "  ${CUUP_IMAGE}"
echo "  ${DU_IMAGE}"
echo "  ${UE_IMAGE}"
echo
echo "Έλεγξε E2 logs (όταν έχεις RIC):"
echo "  kubectl logs -n ${NAMESPACE} deployment/${CUCP_RELEASE} | grep -i e2"
echo "  kubectl logs -n ${NAMESPACE} deployment/${DU_RELEASE}   | grep -i e2"
echo "=================================================================="
