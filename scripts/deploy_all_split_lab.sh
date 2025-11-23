#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# OAI 5G SA Lab - Phase 2 (CU-CP / CU-UP / DU split) on Minikube
# Namespace: oai5g-split
#
# Τι κάνει:
#  - Δημιουργεί/βεβαιώνει το namespace oai5g-split
#  - Κάνει clone το oai-cn5g-fed (Helm charts για Core + RAN)
#  - Deploy OAI 5G Core (IPv4+IPv6 default από τα charts)
#  - Deploy OAI CU-CP, CU-UP, DU, NR-UE (split RAN)
#  - Περιμένει να γίνουν READY
#  - Τρέχει ένα ping test από το UE προς 8.8.8.8
###############################################################################

LAB_ROOT="${HOME}/lab"
LAB_DIR="${LAB_ROOT}/5g-Lab-gnb-split"
REPO_URL_CN5G="https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed.git"
REPO_DIR_CN5G="${LAB_DIR}/oai-cn5g-fed"
NAMESPACE="oai5g-split"

echo "=== [0] Έλεγχος ότι τρέχει το Minikube & έχεις cluster ==="
kubectl cluster-info >/dev/null 2>&1 || {
  echo "❌ kubectl δεν βλέπει cluster. Βεβαιώσου ότι το minikube είναι up (minikube start)."
  exit 1
}

echo "=== [1] Δημιουργία φακέλου lab: ${LAB_DIR} ==="
mkdir -p "${LAB_DIR}"

echo "=== [2] Namespace: ${NAMESPACE} ==="
if ! kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
  kubectl create namespace "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} υπάρχει ήδη."
fi

echo "=== [3] Clone / update oai-cn5g-fed (Helm charts) ==="
if [ -d "${REPO_DIR_CN5G}/.git" ]; then
  echo "Βρέθηκε υπάρχον repo oai-cn5g-fed, κάνω git fetch/pull..."
  cd "${REPO_DIR_CN5G}"
  git fetch origin
  git checkout develop || git checkout master || true
  git pull --rebase || true
else
  cd "${LAB_DIR}"
  git clone "${REPO_URL_CN5G}"
  cd "${REPO_DIR_CN5G}"
fi

echo "Τρέχον repo CN5G: $(pwd)"
ls charts || echo "⚠️ Δεν βλέπω τον φάκελο charts, έλεγξε το repo."

###############################################################################
# 4. Deploy 5G Core (OAI CN5G) στο namespace oai5g-split
###############################################################################
echo "=== [4] Deploy 5G Core στο namespace ${NAMESPACE} ==="

cd "${REPO_DIR_CN5G}"

# Οι Helm charts έχουν dependencies (mysql, nrf, κλπ) – τα φέρνουμε
echo "→ helm dependency update για core chart"
helm dependency update charts/oai-5g-core/oai-5g-basic || true

# Χρησιμοποιούμε τα default values του chart (IPv4+IPv6)
CORE_RELEASE="oai-5g-core-split"

echo "→ helm upgrade --install ${CORE_RELEASE}"
helm upgrade --install "${CORE_RELEASE}" charts/oai-5g-core/oai-5g-basic \
  --namespace "${NAMESPACE}" \
  --create-namespace

echo "=== [4.1] Περιμένω να σηκωθούν τα Core pods (AMF, SMF, UPF, NRF, UDM, UDR, AUSF, MySQL) ==="

# Περιμένουμε συνολικά τα pods στο namespace να είναι Ready (βασικά core NF)
kubectl wait --for=condition=Ready pod -n "${NAMESPACE}" --all --timeout=600s || {
  echo "⚠️ Κάποια core pods δεν έγιναν Ready μέσα στο timeout. Δες τα logs πριν συνεχίσεις."
}

echo "Pods core αυτή τη στιγμή:"
kubectl get pods -n "${NAMESPACE}"

###############################################################################
# 5. Deploy RAN Phase 2: CU-CP, CU-UP, DU, NR-UE
###############################################################################
echo "=== [5] Deploy RAN Phase 2 (CU-CP / CU-UP / DU / NR-UE) ==="

echo "→ helm dependency update για RAN charts"
# Μπορεί να αποτύχουν κάποια dependency updates, δεν είναι κρίσιμο
helm dependency update charts/oai-5g-ran/oai-cu-cp || true
helm dependency update charts/oai-5g-ran/oai-cu-up || true
helm dependency update charts/oai-5g-ran/oai-du    || true
helm dependency update charts/oai-5g-ran/oai-nr-ue || true

# Release names (μπορείς να τα αλλάξεις αν θέλεις)
CUCP_RELEASE="oai-cu-cp-split"
CUUP_RELEASE="oai-cu-up-split"
DU_RELEASE="oai-du-split"
UE_RELEASE="oai-nr-ue-split"

echo "→ Deploy CU-CP"
helm upgrade --install "${CUCP_RELEASE}" charts/oai-5g-ran/oai-cu-cp \
  --namespace "${NAMESPACE}"

echo "→ Deploy CU-UP"
helm upgrade --install "${CUUP_RELEASE}" charts/oai-5g-ran/oai-cu-up \
  --namespace "${NAMESPACE}"

echo "→ Deploy DU"
helm upgrade --install "${DU_RELEASE}" charts/oai-5g-ran/oai-du \
  --namespace "${NAMESPACE}"

echo "→ Deploy NR-UE (RFsim UE)"
helm upgrade --install "${UE_RELEASE}" charts/oai-5g-ran/oai-nr-ue \
  --namespace "${NAMESPACE}"

echo "=== [5.1] Περιμένω RAN pods (CU-CP, CU-UP, DU, UE) να γίνουν Ready ==="

# Περιμένω για κάθε RAN NF ξεχωριστά, με βάση το label app.kubernetes.io/name
# (σύμφωνα με τα oai-cn5g-fed helm charts)
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=oai-cu-cp -n "${NAMESPACE}" --timeout=600s || true
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=oai-cu-up -n "${NAMESPACE}" --timeout=600s || true
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=oai-du    -n "${NAMESPACE}" --timeout=600s || true
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=oai-nr-ue -n "${NAMESPACE}" --timeout=600s || true

echo "=== [5.2] Τελική εικόνα pods στο ${NAMESPACE} ==="
kubectl get pods -n "${NAMESPACE}" -o wide

###############################################################################
# 6. Basic connectivity test (UE → Internet)
###############################################################################
echo "=== [6] Ping test από UE προς 8.8.8.8 (αν όλα είναι ΟΚ) ==="

UE_POD="$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=oai-nr-ue -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"

if [ -z "${UE_POD}" ]; then
  echo "⚠️ Δεν βρήκα UE pod (label app.kubernetes.io/name=oai-nr-ue). Έλεγξε τα pods με:"
  echo "    kubectl get pods -n ${NAMESPACE}"
else
  echo "→ UE pod: ${UE_POD}"
  echo "→ Τρέχω: ping -c 5 8.8.8.8 μέσα στο UE"
  kubectl exec -n "${NAMESPACE}" "${UE_POD}" -- ping -c 5 8.8.8.8 || {
    echo '⚠️ Το ping από UE απέτυχε. Έλεγξε N2/N3/E1/F1 links και logs (oai-amf, oai-smf, oai-upf, oai-cu-cp, oai-cu-up, oai-du, oai-nr-ue).'
  }
fi

echo "=================================================================="
echo "✔ Το Phase 2 5G lab (IPv4+IPv6, CU-CP/CU-UP/DU split) είναι deployed"
echo "  Namespace: ${NAMESPACE}"
echo ""
echo "Χρήσιμες εντολές:"
echo "  kubectl get pods -n ${NAMESPACE} -o wide"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=oai-cu-cp --tail=100"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=oai-cu-up --tail=100"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=oai-du    --tail=100"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=oai-nr-ue --tail=100"
echo "=================================================================="
