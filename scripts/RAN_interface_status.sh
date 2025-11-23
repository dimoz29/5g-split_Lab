#!/usr/bin/env bash
set -euo pipefail

NS="oai5g-split"

GREEN="\e[32m"; RED="\e[31m"; YELLOW="\e[33m"; CYAN="\e[36m"; NC="\e[0m"

PASS="[${GREEN}UP${NC}]"
FAIL="[${RED}DOWN${NC}]"
WARN="[${YELLOW}WARN${NC}]"

print_step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

########################################################
# Helper functions
########################################################

check_logs() {
  local component="$1"
  local pattern="$2"
  local label="$3"

  if kubectl logs -n "$NS" "$component" 2>/dev/null | grep -qiE "$pattern"; then
    echo -e "$PASS $label (logs contain '$pattern')"
    return 0
  else
    echo -e "$WARN $label (no '$pattern' found in logs)"
    return 1
  fi
}

check_port() {
  local component="$1"
  local port="$2"
  local proto="$3"
  local label="$4"

  if kubectl exec -n "$NS" "$component" -- ss -aunp 2>/dev/null | grep -q "$port"; then
    echo -e "$PASS $label (port $port/$proto active)"
    return 0
  else
    echo -e "$WARN $label (port $port/$proto not visible — may be image limitation)"
    return 1
  fi
}

check_sctp() {
  local component="$1"
  local label="$2"

  if kubectl exec -n "$NS" "$component" -- ss -a | grep -qi sctp; then
    echo -e "$PASS $label (SCTP associations exist)"
    return 0
  else
    echo -e "$WARN $label (no SCTP associations found)"
    return 1
  fi
}

########################################################
# START OUTPUT
########################################################

echo -e "${GREEN}"
echo "============================================================"
echo "        OAI 5G RAN INTERFACE STATUS (E1 / F1 / NGAP)"
echo "============================================================"
echo -e "${NC}"

########################################################
# E1 INTERFACE (CU-CP ↔ CU-UP)
########################################################
print_step "E1 INTERFACE (CU-CP ↔ CU-UP)"

check_logs "deploy/oai-cu-cp" "E1|E1AP" "E1-AP on CU-CP"
check_logs "deploy/oai-cu-up" "E1|E1AP" "E1-AP on CU-UP"
check_port "deploy/oai-cu-cp" "2153" "udp" "E1 port on CU-CP"


########################################################
# F1-C (DU ↔ CU-CP) — SCTP SIGNALING
########################################################
print_step "F1-C (DU ↔ CU-CP)"

check_logs "deploy/oai-du" "F1|F1AP" "F1-C on DU"
check_logs "deploy/oai-cu-cp" "F1|F1AP" "F1-C on CU-CP"
check_sctp "deploy/oai-du" "SCTP state on DU"
check_sctp "deploy/oai-cu-cp" "SCTP state on CU-CP"


########################################################
# F1-U (DU ↔ CU-UP) — USER PLANE
########################################################
print_step "F1-U (DU ↔ CU-UP)"

check_logs "deploy/oai-du" "F1U|F1-U" "F1-U on DU"
check_logs "deploy/oai-cu-up" "F1U|F1-U" "F1-U on CU-UP"
check_port "deploy/oai-du" "2153" "udp" "F1-U port on DU"
check_port "deploy/oai-cu-up" "2153" "udp" "F1-U port on CU-UP"


########################################################
# NGAP (RAN ↔ AMF)
########################################################
print_step "NGAP (AMF)"

check_logs "deploy/oai-amf" "NGAP|InitialUEMessage|Registration" "NGAP signaling"


########################################################
# PFCP (SMF ↔ UPF)
########################################################
print_step "PFCP (SMF ↔ UPF)"

check_logs "deploy/oai-upf" "PFCP" "PFCP on UPF"
check_port "deploy/oai-upf" "8805" "udp" "PFCP port on UPF"


########################################################
# GTP-U (CU-UP ↔ UPF)
########################################################
print_step "GTP-U (CU-UP ↔ UPF)"

check_logs "deploy/oai-upf" "GTP" "GTP-U in UPF logs"
check_port "deploy/oai-upf" "2152" "udp" "UPF listening for GTP-U"
check_port "deploy/oai-cu-up" "2152" "udp" "CU-UP GTP-U activity"


########################################################
# END OF SCRIPT
########################################################

echo -e "\n${GREEN}Interface status check completed.${NC}"
echo "✔ Use this tool to see which RAN links are UP at protocol level."
echo "✔ Check logs for deeper signaling traces."
