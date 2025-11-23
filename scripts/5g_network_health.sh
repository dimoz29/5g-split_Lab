#!/usr/bin/env bash
set -euo pipefail

NS="oai5g-split"

GREEN="\e[32m"; RED="\e[31m"; YELLOW="\e[33m"; NC="\e[0m"

print_pass()  { echo -e "${GREEN}[PASS]${NC} $1"; }
print_fail()  { echo -e "${RED}[FAIL]${NC} $1"; }
print_step()  { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

echo -e "${GREEN}"
echo "============================================================"
echo "                OAI 5G NETWORK HEALTH CHECK"
echo "============================================================"
echo -e "${NC}"

###############################################
# A. Kubernetes cluster health
###############################################
print_step "A. Kubernetes cluster health"

kubectl get nodes >/dev/null 2>&1 \
  && print_pass "Kubernetes node reachable" \
  || print_fail "Kubernetes node unreachable"

kubectl get pods -n $NS >/dev/null 2>&1 \
  && print_pass "Namespace '$NS' reachable" \
  || print_fail "Namespace '$NS' not found"


###############################################
# B. Core Network Status
###############################################
print_step "B. 5G CORE (NRF / AMF / SMF / UPF / UDM / AUSF / UDR / LMF)"

core_components=(
  "oai-nrf"
  "oai-amf"
  "oai-smf"
  "oai-upf"
  "oai-udm"
  "oai-udr"
  "oai-ausf"
  "oai-lmf"
)

for c in "${core_components[@]}"; do
  kubectl get deploy/$c -n $NS >/dev/null 2>&1 \
    && print_pass "$c running" \
    || print_fail "$c NOT running"
done


###############################################
# C. RAN SPLIT Status (CU-CP / DU / CU-UP / NR-UE)
###############################################
print_step "C. RAN SPLIT COMPONENTS"

ran_components=(
  "oai-cu-cp"
  "oai-du"
  "oai-cu-up"
  "oai-nr-ue"
)

for r in "${ran_components[@]}"; do
  kubectl get deploy/$r -n $NS >/dev/null 2>&1 \
    && print_pass "$r running" \
    || print_fail "$r NOT running"
done


###############################################
# D. Connectivity Tests (PING & Routing)
###############################################
print_step "D. Connectivity Chain Tests"

# 1) UE → Internet
if kubectl exec -n $NS deploy/oai-nr-ue -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
  print_pass "UE can reach Internet (UE → UPF → WAN)"
else
  print_fail "UE cannot reach Internet"
fi

# 2) AMF → CU-CP (NGAP)
if kubectl exec -n $NS deploy/oai-amf -- ping -c 1 oai-cu-cp >/dev/null 2>&1; then
  print_pass "AMF can reach CU-CP (NGAP OK)"
else
  print_fail "AMF cannot reach CU-CP (NGAP FAIL)"
fi

# 3) CU-CP → DU (F1-C)
if kubectl exec -n $NS deploy/oai-cu-cp -- ping -c 1 oai-du >/dev/null 2>&1; then
  print_pass "CU-CP can reach DU (F1-C OK)"
else
  print_fail "CU-CP cannot reach DU (F1-C FAIL)"
fi

# 4) CU-UP → DU (F1-U data path)
if kubectl exec -n $NS deploy/oai-cu-up -- ping -c 1 oai-du >/dev/null 2>&1; then
  print_pass "CU-UP can reach DU (F1-U OK)"
else
  print_fail "CU-UP cannot reach DU (F1-U FAIL)"
fi

# 5) CU-UP → UPF (GTP-U)
if kubectl exec -n $NS deploy/oai-cu-up -- ping -c 1 oai-upf >/dev/null 2>&1; then
  print_pass "CU-UP can reach UPF (GTP-U OK)"
else
  print_fail "CU-UP cannot reach UPF (GTP-U FAIL)"
fi


###############################################
# E. Interface Debug (NGAP / PFCP / GTP-U / F1 / E1)
###############################################
print_step "E. INTERFACE HEALTH (LOG CHECKS)"

# NGAP
kubectl logs -n $NS deploy/oai-amf | grep -qi ngap \
  && print_pass "NGAP messages detected" \
  || print_fail "No NGAP activity"

# PFCP
kubectl logs -n $NS deploy/oai-upf | grep -qi pfcp \
  && print_pass "PFCP detected between SMF <-> UPF" \
  || print_fail "No PFCP activity"

# GTP-U
kubectl logs -n $NS deploy/oai-upf | grep -qi gtp \
  && print_pass "GTP-U activity detected" \
  || print_fail "No GTP-U activity"

# F1-C
kubectl logs -n $NS deploy/oai-du | grep -qi f1 \
  && print_pass "F1 activity detected" \
  || print_fail "No F1 messages"

# E1 (for split CU)
kubectl logs -n $NS deploy/oai-cu-cp | grep -qi e1 \
  && print_pass "E1 signalling detected" \
  || print_fail "No E1 messages"


###############################################
# F. E2 Agent Status (for CU-CP & DU)
###############################################
print_step "F. E2 Agent Status"

kubectl logs -n $NS deploy/oai-cu-cp | grep -qi e2 \
  && print_pass "CU-CP E2 log entries exist" \
  || print_fail "No E2 activity on CU-CP"

kubectl logs -n $NS deploy/oai-du | grep -qi e2 \
  && print_pass "DU E2 log entries exist" \
  || print_fail "No E2 activity on DU"


###############################################
# G. Summary
###############################################
print_step "G. SUMMARY"

echo -e "${GREEN}Health check completed.${NC}"
echo "Use logs above to diagnose any failing layer."
echo
echo "Recommended next step:"
echo " - If E2 is disabled → apply config and restart CU/DU."
