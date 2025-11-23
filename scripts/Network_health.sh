#!/usr/bin/env bash
set -euo pipefail

NS="oai5g-split"

# Colors
GREEN="\e[32m"; RED="\e[31m"; YELLOW="\e[33m"; CYAN="\e[36m"; NC="\e[0m"

print_pass()  { echo -e "${GREEN}[PASS]${NC} $1"; }
print_fail()  { echo -e "${RED}[FAIL]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_step()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# Arrays for summary
HARD_FAILS=()
WARNINGS=()

echo -e "${GREEN}"
echo "============================================================"
echo "          OAI 5G + E2/FlexRIC NETWORK HEALTH CHECK"
echo "============================================================"
echo -e "${NC}"

###############################################
# 1. K8s HEALTH (Infra + Pods + Basic Connectivity)
###############################################
print_step "1. K8s HEALTH"

# 1.1 Cluster / Namespace
if kubectl get nodes >/dev/null 2>&1; then
  print_pass "Kubernetes node reachable"
else
  print_fail "Kubernetes node unreachable"
  HARD_FAILS+=("K8s API / node unreachable")
fi

if kubectl get ns "$NS" >/dev/null 2>&1; then
  print_pass "Namespace '$NS' reachable"
else
  print_fail "Namespace '$NS' not found"
  HARD_FAILS+=("Namespace $NS missing")
fi

# 1.2 Core Deployments
print_step "1.2 Core Deployments in namespace $NS"

core_deploys=(
  "oai-nrf"
  "oai-amf"
  "oai-smf"
  "oai-upf"
  "oai-udm"
  "oai-udr"
  "oai-ausf"
  "oai-lmf"
)

for d in "${core_deploys[@]}"; do
  if kubectl get deploy/"$d" -n "$NS" >/dev/null 2>&1; then
    ready=$(kubectl get deploy/"$d" -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$ready" == "1" ]]; then
      print_pass "$d deployment Ready (1/1)"
    else
      print_fail "$d deployment exists but not Ready"
      HARD_FAILS+=("$d deployment not Ready")
    fi
  else
    print_fail "$d deployment NOT found"
    HARD_FAILS+=("$d deployment missing")
  fi
done

# 1.3 RAN components (CU-CP / CU-UP / DU / UE pod presence)
print_step "1.3 RAN COMPONENTS (CU-CP / CU-UP / DU / UE)"

ran_deploys=(
  "oai-cu-cp"
  "oai-cu-up"
  "oai-du"
)

for r in "${ran_deploys[@]}"; do
  if kubectl get deploy/"$r" -n "$NS" >/dev/null 2>&1; then
    ready=$(kubectl get deploy/"$r" -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$ready" == "1" ]]; then
      print_pass "$r deployment Ready (1/1)"
    else
      print_fail "$r deployment exists but not Ready"
      HARD_FAILS+=("$r deployment not Ready")
    fi
  else
    print_fail "$r deployment NOT found"
    HARD_FAILS+=("$r deployment missing")
  fi
done

# UE pod (not deployment)
UE_POD="$(kubectl get pod -n "$NS" -l app=oai-nr-ue -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$UE_POD" ]]; then
  print_pass "oai-nr-ue pod present: $UE_POD"
else
  print_fail "oai-nr-ue pod NOT found"
  HARD_FAILS+=("UE pod (oai-nr-ue) missing")
fi

# 1.4 FlexRIC (near-RT RIC) deployment
print_step "1.4 FlexRIC (near-RT RIC) Deployment"

if kubectl get deploy/oai-flexric -n "$NS" >/dev/null 2>&1; then
  ready=$(kubectl get deploy/oai-flexric -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ "$ready" == "1" ]]; then
    print_pass "oai-flexric deployment Ready (1/1)"
  else
    print_fail "oai-flexric deployment exists but not Ready"
    HARD_FAILS+=("oai-flexric deployment not Ready (E2/RIC not available)")
  fi
else
  print_warn "oai-flexric deployment NOT found (E2/RIC not deployed?)"
  WARNINGS+=("oai-flexric missing – ignore if lab does not use E2/FlexRIC")
fi

# 1.5 K8s-level connectivity (pings between services/pods) – SOFT CHECKS
print_step "1.5 K8s-LEVEL CONNECTIVITY (soft checks)"

# AMF → CU-CP via svc oai-cu
if kubectl exec -n "$NS" deploy/oai-amf -- ping -c 1 oai-cu >/dev/null 2>&1; then
  print_pass "AMF can ping service oai-cu (CU-CP)"
else
  print_warn "AMF cannot ping service oai-cu (CU-CP) – may be normal with SCTP-only setup"
  WARNINGS+=("AMF → oai-cu ping failed (check service oai-cu / DNS / protocol expectations)")
fi

# CU-CP → DU via oai-ran
if kubectl exec -n "$NS" deploy/oai-cu-cp -- ping -c 1 oai-ran >/dev/null 2>&1; then
  print_pass "CU-CP can ping oai-ran (DU aggregator)"
else
  print_warn "CU-CP cannot ping oai-ran – check service oai-ran and DU"
  WARNINGS+=("CU-CP → oai-ran ping failed (K8s-level connectivity)")
fi

# CU-UP → DU via oai-ran
if kubectl exec -n "$NS" deploy/oai-cu-up -- ping -c 1 oai-ran >/dev/null 2>&1; then
  print_pass "CU-UP can ping oai-ran (DU aggregator)"
else
  print_warn "CU-UP cannot ping oai-ran – check service oai-ran, CU-UP DNS"
  WARNINGS+=("CU-UP → oai-ran ping failed (K8s-level connectivity)")
fi

# CU-UP → UPF via oai-upf
if kubectl exec -n "$NS" deploy/oai-cu-up -- ping -c 1 oai-upf >/dev/null 2>&1; then
  print_pass "CU-UP can ping UPF (oai-upf)"
else
  print_warn "CU-UP cannot ping UPF – may be image limitation (no ping) or DNS issue"
  WARNINGS+=("CU-UP → oai-upf ping failed (K8s-level connectivity)")
fi


###############################################
# 2. 5G NETWORK E2E (Hard functional checks)
###############################################
print_step "2. 5G NETWORK E2E"

# 2.1 UE → Internet (data plane)
if [[ -n "$UE_POD" ]] && kubectl exec -n "$NS" "$UE_POD" -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
  print_pass "UE can reach Internet (UE → RAN → CU-UP → UPF → WAN)"
else
  print_fail "UE cannot reach Internet (attach/data path problem)"
  HARD_FAILS+=("UE → Internet ping failed (check GTP-U / PFCP / SMF-UPF / routes)")
fi


###############################################
# 3. E2 / FlexRIC CONNECTIVITY (CU-CP ↔ RIC)
###############################################
print_step "3. E2 / FlexRIC CONNECTIVITY"

# 3.1 CU-CP → FlexRIC SCTP (port 36421)
E2_CUCP_SCTP=$(kubectl exec -n "$NS" deploy/oai-cu-cp \
  -- sh -c 'ss -na 2>/dev/null | grep 36421 || true' 2>/dev/null || true)

if [[ -n "$E2_CUCP_SCTP" ]]; then
  # Ideally contains ESTAB; we just print what we saw
  if grep -qi "ESTAB" <<< "$E2_CUCP_SCTP"; then
    print_pass "E2 SCTP CU-CP → RIC on 36421 is ESTABLISHED:"
    echo "$E2_CUCP_SCTP"
  else
    print_warn "CU-CP has SCTP socket on 36421, but not ESTAB (check E2Setup/E2AP logs):"
    echo "$E2_CUCP_SCTP"
    WARNINGS+=("CU-CP SCTP to 36421 present but not ESTAB – inspect E2AP/E2Setup")
  fi
else
  print_warn "No SCTP socket to 36421 visible from CU-CP (E2 may be disabled or misconfigured)"
  WARNINGS+=("No E2 SCTP from CU-CP to RIC – check e2_agent, -E flag, near_ric_ip_addr/e2_port")
fi

# 3.2 FlexRIC (RIC) SCTP listener on 36421 (best-effort)
E2_RIC_SCTP=$(kubectl exec -n "$NS" deploy/oai-flexric \
  -- sh -c 'ss -na 2>/dev/null | grep 36421 || true' 2>/dev/null || true)

if [[ -n "$E2_RIC_SCTP" ]]; then
  if grep -qi "LISTEN" <<< "$E2_RIC_SCTP"; then
    print_pass "FlexRIC listens on E2 port 36421:"
    echo "$E2_RIC_SCTP"
  else
    print_warn "FlexRIC has 36421 in ss output but no LISTEN line – check nearRT-RIC config:"
    echo "$E2_RIC_SCTP"
    WARNINGS+=("FlexRIC ss output for 36421 looks odd – verify NEAR_RIC_IP/E2_Port in flexric.conf")
  fi
else
  print_warn "Could not detect 36421 via 'ss' in oai-flexric (no iproute2 or no SCTP listener)"
  WARNINGS+=("No visible E2 (36421) listener on FlexRIC – check image/iproute2 and flexric.conf")
fi


###############################################
# 4. LOG INFO (NGAP / PFCP / GTP-U / F1 / E1 / E2/RIC)
###############################################
print_step "4. LOG INFO (protocol activity – informational)"

# NGAP (AMF)
if kubectl logs -n "$NS" deploy/oai-amf 2>/dev/null | grep -qi ngap; then
  print_pass "NGAP messages detected in AMF logs"
else
  print_warn "No NGAP keyword detected in AMF logs (may still be OK, check manually if needed)"
  WARNINGS+=("No NGAP pattern in AMF logs – check registration logs if issues appear")
fi

# PFCP (UPF)
if kubectl logs -n "$NS" deploy/oai-upf 2>/dev/null | grep -qi pfcp; then
  print_pass "PFCP messages detected in UPF logs"
else
  print_warn "No PFCP pattern detected in UPF logs"
  WARNINGS+=("No PFCP pattern in UPF logs – if UE has no data, inspect UPF/SMF logs")
fi

# GTP-U (UPF)
if kubectl logs -n "$NS" deploy/oai-upf 2>/dev/null | grep -qi gtp; then
  print_pass "GTP-U activity detected in UPF logs"
else
  print_warn "No GTP keyword detected in UPF logs"
  WARNINGS+=("No GTP-U pattern in UPF logs – if data plane fails, check GTP tunnels")
fi

# F1 (DU)
if kubectl logs -n "$NS" deploy/oai-du 2>/dev/null | grep -qi f1; then
  print_pass "F1 activity detected in DU logs"
else
  print_warn "No F1 pattern detected in DU logs – if RAN issues, inspect DU/CU-CP logs"
  WARNINGS+=("No F1 pattern in DU logs – if attach fails, check F1AP")
fi

# E1 (CU-CP / CU-UP)
if kubectl logs -n "$NS" deploy/oai-cu-cp 2>/dev/null | grep -qi e1; then
  print_pass "E1 signalling detected in CU-CP logs"
else
  print_warn "No E1 pattern detected in CU-CP logs – if split issues, inspect CU-CP/CU-UP"
  WARNINGS+=("No E1 pattern in CU-CP logs – if CU-UP problems, inspect E1AP")
fi

# E2 (CU-CP)
if kubectl logs -n "$NS" deploy/oai-cu-cp 2>/dev/null | grep -qi e2; then
  print_pass "CU-CP E2 log entries exist"
else
  print_warn "No E2 activity visible on CU-CP logs – only relevant if E2 is enabled"
  WARNINGS+=("No E2 pattern on CU-CP logs – if E2 issues, inspect nr-softmodem startup/E2 agent")
fi

# E2 (FlexRIC logs – may be empty if image logs elsewhere)
if kubectl logs -n "$NS" deploy/oai-flexric 2>/dev/null | grep -qi e2; then
  print_pass "FlexRIC logs contain E2-related entries"
else
  print_warn "No E2 pattern detected in FlexRIC logs (may log elsewhere or at lower verbosity)"
  WARNINGS+=("No E2 pattern in FlexRIC logs – if E2 fails, inspect nearRT-RIC config/logging")
fi


###############################################
# 5. PROPOSAL FOR FIXING ISSUES
###############################################
print_step "5. PROPOSAL FOR FIXING ISSUES"

if ((${#HARD_FAILS[@]} == 0)) && ((${#WARNINGS[@]} == 0)); then
  echo -e "${GREEN}Overall status: ALL GOOD – no hard failures or warnings detected.${NC}"
else
  if ((${#HARD_FAILS[@]} > 0)); then
    echo -e "${RED}HARD FAILS (must be fixed for a healthy lab):${NC}"
    for f in "${HARD_FAILS[@]}"; do
      echo "  - $f"
    done

    echo
    echo "Suggested steps for HARD FAILS:"
    echo "  1) Check pod status:   kubectl get pods -n $NS"
    echo "  2) For each failing component:"
    echo "     - kubectl describe deploy/<name> -n $NS"
    echo "     - kubectl logs deploy/<name> -n $NS"
    echo "  3) If UE → Internet fails:"
    echo "     - Inspect SMF & UPF logs (PFCP errors):"
    echo "         kubectl logs -n $NS deploy/oai-smf"
    echo "         kubectl logs -n $NS deploy/oai-upf"
    echo "     - Confirm GTP-U config & routes on UPF."
    echo "  4) If a deployment is missing:"
    echo "     - Check Helm release status (e.g. 'helm list -n $NS')."
    echo "  5) If oai-flexric / E2 fails hard:"
    echo "     - Verify E2 agent config in CU-CP (e2_agent block, -E flag)."
    echo "     - Verify FlexRIC flexric.conf (E2_Port, NEAR_RIC_IP, SM_DIR)."
    echo "     - Check SCTP state with 'ss -na' inside CU-CP and FlexRIC pods."
  else
    echo -e "${GREEN}No HARD FAILS detected.${NC}"
  fi

  echo

  if ((${#WARNINGS[@]} > 0)); then
    echo -e "${YELLOW}WARNINGS (soft checks; investigate only if you see issues in practice):${NC}"
    for w in "${WARNINGS[@]}"; do
      echo "  - $w"
    done

    echo
    echo "Suggested steps for WARNINGS:"
    echo "  - For K8s-level ping warnings:"
    echo "      * Verify the corresponding Service exists (kubectl get svc -n $NS)."
    echo "      * Check if the component image actually has 'ping' installed."
    echo "      * Remember: SCTP/UDP services won't always behave well with simple ICMP/TCP checks."
    echo "  - For log-related warnings:"
    echo "      * Manually inspect detailed logs for AMF/SMF/UPF/CU-CP/CU-UP/DU/FlexRIC."
    echo "      * Correlate with real UE behaviour (attach, data plane, E2 behaviour, etc.)."
    echo "  - For E2/FlexRIC connectivity warnings:"
    echo "      * Confirm near_ric_ip_addr/e2_port in CU-CP config."
    echo "      * Confirm FlexRIC listens on 36421 and SM_DIR points to valid SM libs."
  else
    echo -e "${GREEN}No WARNINGS detected.${NC}"
  fi
fi

echo
echo -e "${GREEN}Health check completed.${NC}"
echo "K8s = infra status, 5G e2e = real UE/data-path, E2/FlexRIC = control-path to RIC, Log info = protocol-level hints."
