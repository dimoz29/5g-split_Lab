#!/bin/bash

NS="oai5g-split"
TS=$(date +"%Y%m%d-%H%M%S")
BACKUP_DIR="./backup_revert_${TS}"

echo "============================================================"
echo "   OAI 5G RAN AUTO-REVERT (oai-ran → oai-cu)"
echo "   Namespace: $NS"
echo "   Backup: $BACKUP_DIR"
echo "============================================================"

mkdir -p "$BACKUP_DIR"

echo "[1] Collecting candidate ConfigMaps..."
for cm in $(kubectl get configmap -n $NS -o name | grep -E "oai-(cu|du)"); do
    echo "   → Backing up $cm"
    kubectl get $cm -n $NS -o yaml > "$BACKUP_DIR/${cm##*/}.yaml"
done
echo "✔ Backups complete"

echo ""
echo "[2] Applying automated patch: oai-ran → oai-cu"
for cm in $(kubectl get configmap -n $NS -o name | grep -E "oai-(cu|du)"); do
    echo "   → Patching $cm"
    kubectl get $cm -n $NS -o yaml \
    | sed 's/remote_s_address *= *"oai-ran"/remote_s_address = "oai-cu"/g' \
    | sed 's/remote_n_address *= *"oai-ran"/remote_n_address = "oai-cu"/g' \
    | kubectl apply -f -
done
echo "✔ Patch applied"

echo ""
echo "[3] Restarting all involved deployments (CU-CP / CU-UP / DU)..."
kubectl rollout restart deploy/oai-cu-cp -n $NS
kubectl rollout restart deploy/oai-cu-up -n $NS
kubectl rollout restart deploy/oai-du -n $NS
echo "✔ Rollouts triggered"

echo ""
echo "[4] Waiting for deployments..."
kubectl rollout status deploy/oai-cu-cp -n $NS
kubectl rollout status deploy/oai-cu-up -n $NS
kubectl rollout status deploy/oai-du -n $NS

echo ""
echo "[5] Showing endpoints + pod status..."
kubectl get endpoints -n $NS | grep oai-cu
kubectl get pods -n $NS -o wide | grep -E 'oai-cu|oai-du'

echo ""
echo "============================================================"
echo " DONE — System reverted from oai-ran → oai-cu"
echo "============================================================"
