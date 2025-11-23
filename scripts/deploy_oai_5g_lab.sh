#!/usr/bin/env bash
set -euo pipefail

# -------------- CONFIG -----------------
LAB_DIR="${HOME}/lab/5g-lab"
REPO_URL="https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed.git"
REPO_DIR="${LAB_DIR}/oai-cn5g-fed"
NAMESPACE="oai5g"
PROFILE="minikube"
# ---------------------------------------

echo ""
echo "======================================================"
echo "    OAI FULL 5G LAB DEPLOYMENT (CORE + gNB + UE)"
echo "======================================================"
echo ""

# --- CHECK 1: Minikube running ---
echo "[1/9] Ελέγχω αν το Minikube είναι ενεργό..."
if ! minikube status | grep -q "host: Running"; then
  echo "❌ Το Minikube ΔΕΝ τρέχει."
  echo "➡️  Τρέξε:   minikube start"
  exit 1
fi
echo "✅ Minikube είναι ενεργό."

# --- CHECK 2: Tools ---
echo "[2/9] Έλεγχος απαιτούμενων εργαλείων..."
for cmd in kubectl helm git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Λείπει το εργαλείο: $cmd"
    exit 1
  fi
done
echo "✅ Όλα τα tools υπάρχουν."

# --- PREPARE FOLDERS ---
echo "[3/9] Δημιουργία φακέλων Lab..."
mkdir -p "${LAB_DIR}"
echo "📁 LAB root: ${LAB_DIR}"

# --- GIT CLONE ---
echo "[4/9] Clone / Update του OAI CN5G repo..."
if [ -d "${REPO_DIR}/.git" ]; then
    echo "➡️ Repo υπάρχει ήδη, κάνω git pull..."
    cd "${REPO_DIR}"
    git pull --rebase
else
    echo "➡️ Κάνω clone το repo..."
    cd "${LAB_DIR}"
    git clone "${REPO_URL}" "$(basename ${REPO_DIR})"
    cd "${REPO_DIR}"
fi
echo "📍 Repo directory: ${REPO_DIR}"

# --- K8s Namespace ---
echo "[5/9] Δημιουργία namespace '${NAMESPACE}'..."
kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}"

# --- ADD HELM REPO (LOCAL) ---
echo "[6/9] Update Helm dependencies..."
cd "${REPO_DIR}"

# ----------------------------
# 5G CORE DEPLOYMENT
# ----------------------------
CORE_CHART="charts/oai-5g-core/oai-5g-basic"

if [ ! -d "${CORE_CHART}" ]; then
  echo "❌ Δεν βρέθηκε το chart: ${CORE_CHART}"
  echo "    Η δομή μπορεί να άλλαξε. Πες μου να σου το φτιάξω."
  exit 1
fi

echo "[7/9] Deploy OAI 5G Core..."
helm dependency update "${CORE_CHART}"

if helm -n "${NAMESPACE}" status oai-5g-core >/dev/null 2>&1; then
    helm upgrade oai-5g-core "${CORE_CHART}" -n "${NAMESPACE}"
else
    helm install oai-5g-core "${CORE_CHART}" -n "${NAMESPACE}"
fi

# ----------------------------
# RAN (gNB + NR-UE)
# ----------------------------
GNB_CHART="charts/oai-5g-ran/oai-gnb"
UE_CHART="charts/oai-5g-ran/oai-nr-ue"

echo "[8/9] Deploy OAI gNB & UE (RAN)..."

if [ ! -d "${GNB_CHART}" ] || [ ! -d "${UE_CHART}" ]; then
  echo "❌ Δεν βρέθηκαν τα RAN charts."
  echo "   Δώσε μου το tree των charts/ για να το διορθώσω."
  exit 1
fi

helm dependency update "${GNB_CHART}" || true
helm dependency update "${UE_CHART}" || true

if helm -n "${NAMESPACE}" status oai-gnb >/dev/null 2>&1; then
    helm upgrade oai-gnb "${GNB_CHART}" -n "${NAMESPACE}"
else
    helm install oai-gnb "${GNB_CHART}" -n "${NAMESPACE}"
fi

if helm -n "${NAMESPACE}" status oai-nr-ue >/dev/null 2>&1; then
    helm upgrade oai-nr-ue "${UE_CHART}" -n "${NAMESPACE}"
else
    helm install oai-nr-ue "${UE_CHART}" -n "${NAMESPACE}"
fi

# ----------------------------
# WAIT FOR PODS
# ----------------------------
echo "[9/9] Περιμένω τα pods να γίνουν Ready..."
kubectl wait --namespace "${NAMESPACE}" \
  --for=condition=Ready pod --all --timeout=600s || true

echo ""
echo "======================================================"
echo " 🎉 ΟΛΟΚΛΗΡΩΘΗΚΕ ΤΟ ΟΑΙ FULL 5G LAB"
echo " Namespace: ${NAMESPACE}"
echo "======================================================"
echo ""
echo "🔍 Έλεγχος κατάστασης pods:"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "📡 Logs AMF:"
echo "   kubectl logs -n ${NAMESPACE} deployment/oai-amf -f"
echo ""
echo "📡 Logs gNB:"
echo "   kubectl logs -n ${NAMESPACE} deployment/oai-gnb -f"
echo ""
echo "📡 Logs NR-UE:"
echo "   kubectl logs -n ${NAMESPACE} deployment/oai-nr-ue -f"
echo ""
