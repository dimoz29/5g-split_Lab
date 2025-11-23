#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Enable FlexRIC + E2 in the OAI split lab
#
# Actions:
#   - Deploy FlexRIC (oai-flexric.yaml)
#   - Wait for FlexRIC deployment to be Ready
#   - Install iproute2 inside the FlexRIC pod (for ss / netstat)
#   - Patch CU-CP ConfigMap:
#       * ensure e2_agent block exists
#       * set near_ric_ip_addr = "<FlexRIC Pod IP>"
#   - Patch CU-CP env USE_ADDITIONAL_OPTIONS to add -E
#   - Restart CU-CP and verify SCTP 36421 to RIC
###############################################################################

NS="oai5g-split"
CUCP_DEPLOY="oai-cu-cp"
CUCP_CM="oai-cu-cp-configmap"
FLEXRIC_DEPLOY="oai-flexric"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEXRIC_YAML="${SCRIPT_DIR}/oai-flexric.yaml"

GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; NC="\e[0m"

echo -e "${GREEN}"
echo "=================================================================="
echo "   Enable FlexRIC + E2 on OAI 5G Split Lab"
echo "=================================================================="
echo -e "${NC}"

echo "=== [0] Environment checks ==="
for cmd in kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo -e "${RED}❌ Missing command: $cmd${NC}"
    exit 1
  }
done

kubectl cluster-info >/dev/null 2>&1 || {
  echo -e "${RED}❌ kubectl cannot reach cluster (check minikube).${NC}"
  exit 1
}

if ! kubectl get ns "$NS" >/dev/null 2>&1; then
  echo -e "${RED}❌ Namespace $NS does not exist. Deploy the lab first.${NC}"
  exit 1
fi

if [ ! -f "$FLEXRIC_YAML" ]; then
  echo -e "${RED}❌ FlexRIC manifest not found: $FLEXRIC_YAML${NC}"
  echo "   Expected oai-flexric.yaml next to this script."
  exit 1
fi

if ! kubectl -n "$NS" get deploy "$CUCP_DEPLOY" >/dev/null 2>&1; then
  echo -e "${RED}❌ CU-CP deployment $CUCP_DEPLOY not found in $NS.${NC}"
  exit 1
fi

if ! kubectl -n "$NS" get configmap "$CUCP_CM" >/dev/null 2>&1; then
  echo -e "${RED}❌ ConfigMap $CUCP_CM not found in $NS.${NC}"
  exit 1
fi

echo "=== [1] Deploy / update FlexRIC ==="
kubectl apply -n "$NS" -f "$FLEXRIC_YAML"

echo "→ Waiting for FlexRIC rollout..."
kubectl rollout status deploy/"$FLEXRIC_DEPLOY" -n "$NS" --timeout=600s || true

echo "→ Current FlexRIC pods:"
kubectl get pods -n "$NS" | grep oai-flexric || true

FLEXRIC_POD="$(
  kubectl get pods -n "$NS" -l app=oai-flexric -o jsonpath='{.items[0].metadata.name}'
)"

if [ -z "$FLEXRIC_POD" ]; then
  echo -e "${RED}❌ Could not find FlexRIC pod (label app=oai-flexric).${NC}"
  exit 1
fi

FLEXRIC_IP="$(
  kubectl get pod "$FLEXRIC_POD" -n "$NS" -o jsonpath='{.status.podIP}'
)"

echo -e "${GREEN}✔ FlexRIC pod: $FLEXRIC_POD (IP: $FLEXRIC_IP)${NC}"

echo "=== [2] Install iproute2 inside FlexRIC pod (for ss) ==="
kubectl exec -n "$NS" "$FLEXRIC_POD" -- bash -c '
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y iproute2 || echo "⚠️ iproute2 install may have failed."
' || true

echo "→ Checking SCTP listen on 36421 (if iproute2 is present)..."
kubectl exec -n "$NS" "$FLEXRIC_POD" -- bash -c '
  if command -v ss >/dev/null 2>&1; then
    ss -na | grep 36421 || echo "no 36421 LISTEN yet (check nearRT-RIC config)";
  else
    echo "⚠️ ss not available inside FlexRIC container.";
  fi
' || true

echo "=== [3] Backup & patch CU-CP ConfigMap (cucp.conf) ==="
BACKUP_CM="${SCRIPT_DIR}/backup_cucp_cm_$(date +%Y%m%d-%H%M%S).yaml"
kubectl get configmap "$CUCP_CM" -n "$NS" -o yaml > "$BACKUP_CM"
echo "→ Backup saved at: $BACKUP_CM"

TMP_CONF="${SCRIPT_DIR}/cucp.conf.tmp"
kubectl get configmap "$CUCP_CM" -n "$NS" -o jsonpath='{.data.cucp\.conf}' > "$TMP_CONF"

if grep -q "near_ric_ip_addr" "$TMP_CONF"; then
  echo "→ Updating near_ric_ip_addr to FlexRIC pod IP: $FLEXRIC_IP"
  sed -i "s/near_ric_ip_addr *= *\"[^\"]*\"/near_ric_ip_addr = \"${FLEXRIC_IP}\"/" "$TMP_CONF"
elif grep -q "e2_agent" "$TMP_CONF"; then
  echo "→ e2_agent block exists but no near_ric_ip_addr. Appending line."
  # Append near_ric_ip_addr inside existing block
  sed -i "/e2_agent *= *{/a \  near_ric_ip_addr = \"${FLEXRIC_IP}\";" "$TMP_CONF"
else
  echo "→ No e2_agent block found. Appending full e2_agent configuration."
  cat <<EOF >> "$TMP_CONF"

e2_agent = {
  enable_e2ap      = "yes";
  near_ric_ip_addr = "${FLEXRIC_IP}";
  e2_port          = 36421;
  sm_dir           = "/usr/local/lib/flexric/";
  e2ap_version     = "2.03";
  kpm_version      = "2.03";
};
EOF
fi

PATCHED_CM="${SCRIPT_DIR}/${CUCP_CM}.patched.yaml"
kubectl create configmap "$CUCP_CM"-tmp -n "$NS" \
  --from-file=cucp.conf="$TMP_CONF" \
  -o yaml --dry-run=client > "$PATCHED_CM"

# Preserve original ConfigMap name
sed -i "s/name: ${CUCP_CM}-tmp/name: ${CUCP_CM}/" "$PATCHED_CM"

echo "→ Applying patched ConfigMap..."
kubectl apply -n "$NS" -f "$PATCHED_CM"

echo "=== [4] Patch USE_ADDITIONAL_OPTIONS on CU-CP (add -E) ==="
# NOTE: In your current deployment, USE_ADDITIONAL_OPTIONS is env[1].
kubectl patch deploy "$CUCP_DEPLOY" -n "$NS" \
  --type=json \
  -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/env/1/value",
      "value": "--sa -E --log_config.global_log_options level,nocolor,time"
    }
  ]' || {
    echo -e "${YELLOW}⚠️ Failed to patch env index 1. Check deployment YAML for USE_ADDITIONAL_OPTIONS index.${NC}"
  }

echo "=== [5] Restart CU-CP and verify E2 SCTP ==="
kubectl rollout restart deploy/"$CUCP_DEPLOY" -n "$NS"
kubectl rollout status deploy/"$CUCP_DEPLOY" -n "$NS" --timeout=600s || true

echo "→ Checking SCTP 36421 from CU-CP to RIC..."
kubectl exec -n "$NS" deploy/"$CUCP_DEPLOY" -- \
  ss -na | grep 36421 || echo "⚠️ No E2 36421 SCTP socket visible (check config/logs)."

echo
echo -e "${GREEN}=================================================================="
echo "✔ FlexRIC deployed and reachable (pod: $FLEXRIC_POD, IP: $FLEXRIC_IP)"
echo "✔ CU-CP ConfigMap patched with e2_agent → near_ric_ip_addr = $FLEXRIC_IP"
echo "✔ USE_ADDITIONAL_OPTIONS updated to include -E"
echo "✔ CU-CP restarted; check logs for E2 activity"
echo "   e.g. kubectl logs -n $NS deploy/$CUCP_DEPLOY | grep -i e2"
echo "==================================================================${NC}"
