#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="oai5g-split"
WORKDIR="$(pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

echo "============================================================"
echo "   OAI 5G RAN F1 AUTO-PATCH (CU-CP <-> DU via oai-ran)"
echo "   Namespace: ${NAMESPACE}"
echo "   Timestamp: ${TS}"
echo "============================================================"
echo

# 0. Basic checks
echo "[0] Checking tools and namespace..."
for cmd in kubectl sed grep; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ Missing command: $cmd"; exit 1; }
done

kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || {
  echo "❌ Namespace ${NAMESPACE} not found."
  exit 1
}

echo "✔ Namespace OK"
echo

# 1. Check that oai-ran service exists
echo "[1] Checking oai-ran Service..."
if ! kubectl get svc oai-ran -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Service oai-ran not found in namespace ${NAMESPACE}"
  echo "   Cannot patch configs to use oai-ran."
  exit 1
fi
echo "✔ Service oai-ran exists"
echo

# 2. Backup current ConfigMaps
BACKUP_DIR="${WORKDIR}/backup_f1_${TS}"
mkdir -p "${BACKUP_DIR}"

echo "[2] Backing up current ConfigMaps to: ${BACKUP_DIR}"
kubectl get configmap oai-cu-cp-configmap -n "${NAMESPACE}" -o yaml > "${BACKUP_DIR}/oai-cu-cp-configmap.yaml"
kubectl get configmap oai-du-configmap    -n "${NAMESPACE}" -o yaml > "${BACKUP_DIR}/oai-du-configmap.yaml"
echo "✔ Backups created"
echo

# 3. Generate patched CU-CP ConfigMap (remote_s_address -> oai-ran)
echo "[3] Patching CU-CP ConfigMap (remote_s_address)..."
CU_SRC="${BACKUP_DIR}/oai-cu-cp-configmap.yaml"
CU_NEW="${WORKDIR}/oai-cu-cp-configmap.patched.yaml"

sed 's/remote_s_address = "oai-du"/remote_s_address = "oai-ran"/' "${CU_SRC}" > "${CU_NEW}"

if ! grep -q 'remote_s_address = "oai-ran"' "${CU_NEW}"; then
  echo "⚠ Warning: remote_s_address pattern not found in CU-CP config."
  echo "  Check ${CU_NEW} manually."
else
  echo "✔ CU-CP now uses remote_s_address = \"oai-ran\""
fi
echo

# 4. Generate patched DU ConfigMap (remote_n_address -> oai-ran)
echo "[4] Patching DU ConfigMap (remote_n_address)..."
DU_SRC="${BACKUP_DIR}/oai-du-configmap.yaml"
DU_NEW="${WORKDIR}/oai-du-configmap.patched.yaml"

sed -e 's/remote_n_address = "@F1_DU_IP_ADDRESS@"/remote_n_address = "oai-ran"/' \
    -e 's/remote_n_address = "@CU_IP_ADDRESS@"/remote_n_address = "oai-ran"/' \
    -e 's/remote_n_address = "oai-cu"/remote_n_address = "oai-ran"/' \
    -e 's/remote_n_address = "oai-cu-cp"/remote_n_address = "oai-ran"/' \
    "${DU_SRC}" > "${DU_NEW}"

if ! grep -q 'remote_n_address = "oai-ran"' "${DU_NEW}"; then
  echo "⚠ Warning: remote_n_address pattern not found in DU config."
  echo "  Check ${DU_NEW} manually."
else
  echo "✔ DU now uses remote_n_address = \"oai-ran\""
fi
echo

# 5. Apply patched ConfigMaps
echo "[5] Applying patched ConfigMaps..."
kubectl apply -f "${CU_NEW}" >/dev/null
kubectl apply -f "${DU_NEW}" >/dev/null
echo "✔ ConfigMaps applied"
echo

# 6. Restart CU-CP & DU deployments
echo "[6] Restarting CU-CP and DU deployments..."
kubectl rollout restart deploy/oai-cu-cp -n "${NAMESPACE}"
kubectl rollout restart deploy/oai-du    -n "${NAMESPACE}"
echo "✔ Rollout restart triggered"
echo

# 7. Wait for rollout to complete
echo "[7] Waiting for CU-CP rollout..."
kubectl rollout status deploy/oai-cu-cp -n "${NAMESPACE}" --timeout=300s || echo "⚠ CU-CP rollout may have issues."

echo "[7] Waiting for DU rollout..."
kubectl rollout status deploy/oai-du -n "${NAMESPACE}" --timeout=300s || echo "⚠ DU rollout may have issues."
echo

# 8. Quick verification
echo "[8] Quick verification (pods + basic logs)..."
echo
kubectl get pods -n "${NAMESPACE}" -o wide | grep -E 'oai-cu-cp|oai-du|NAME'
echo

echo "--- CU-CP F1 logs (last 20 lines) ---"
kubectl logs deploy/oai-cu-cp -n "${NAMESPACE}" --tail=200 | grep -E 'F1AP|SCTP|E1AP' | tail -n 20 || true
echo

echo "--- DU init container logs (last 20 lines) ---"
kubectl logs deploy/oai-du -n "${NAMESPACE}" -c init --tail=50 || true
echo

# 9. DNS check for oai-ran from AMF (if possible)
echo "[9] DNS check: nslookup oai-ran from AMF (if pod exists)..."
AMF_POD="$(kubectl get pod -n "${NAMESPACE}" -l app=oai-amf -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo '')"

if [ -n "${AMF_POD}" ]; then
  kubectl exec -n "${NAMESPACE}" -it "${AMF_POD}" -- nslookup oai-ran || echo "⚠ nslookup oai-ran failed from AMF"
else
  echo "⚠ No AMF pod found with label app=oai-amf, skipping DNS test."
fi

echo
echo "============================================================"
echo "   DONE."
echo "   - Backups: ${BACKUP_DIR}"
echo "   - Patched Configs: ${CU_NEW}, ${DU_NEW}"
echo "   - Check F1/E1/NGAP flows in CU-CP & DU logs."
echo "============================================================"
