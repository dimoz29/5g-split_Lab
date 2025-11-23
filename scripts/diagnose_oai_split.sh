#!/bin/bash

NS="oai5g-split"

divider() { echo "------------------------------------------------------------"; }

section() {
  divider
  echo -e "\e[1;36m$1\e[0m"
  divider
}

ok() { echo -e "  ✔ \e[32m$1\e[0m"; }
fail() { echo -e "  ✘ \e[31m$1\e[0m"; }
warn() { echo -e "  ⚠ \e[33m$1\e[0m"; }

check_dns() {
  local host=$1
  if getent hosts $host >/dev/null 2>&1; then
     local ip=$(getent hosts $host | awk '{print $1}')
     ok "DNS resolves $host → $ip"
  else
     fail "DNS cannot resolve host: $host"
  fi
}

check_service() {
  local svc=$1
  if kubectl get svc $svc -n $NS >/dev/null 2>&1; then
     ok "Service exists: $svc"
     kubectl get svc $svc -n $NS -o wide
  else
     fail "Missing service: $svc"
  fi
}

check_deploy() {
  local dep=$1
  if kubectl get deploy $dep -n $NS >/dev/null 2>&1; then
    ready=$(kubectl get deploy $dep -n $NS -o jsonpath='{.status.readyReplicas}')
    spec=$(kubectl get deploy $dep -n $NS -o jsonpath='{.status.replicas}')
    if [[ "$ready" == "$spec" ]]; then
       ok "Deployment $dep: READY ($ready/$spec)"
    else
       fail "Deployment $dep NOT READY ($ready/$spec)"
       kubectl get pods -n $NS -l app=${dep} -o wide
    fi
  else
    fail "Missing deployment: $dep"
  fi
}

check_configmap_placeholders() {
  local cm=$1
  bad=$(kubectl get configmap $cm -n $NS -o yaml | grep -E "@[A-Z0-9_]+@" | wc -l)
  if [[ $bad -gt 0 ]]; then
     fail "ConfigMap $cm has unresolved placeholders ($bad found)"
     kubectl get configmap $cm -n $NS -o yaml | grep "@"
  else
     ok "ConfigMap $cm OK (no leftover @PLACEHOLDERS@)"
  fi
}

section "CHECKING DEPLOYMENTS STATUS"

deps=(
  oai-amf oai-smf oai-upf oai-nrf oai-udm oai-udr oai-ausf oai-lmf
  oai-cu-cp oai-cu-up oai-du oai-nr-ue
)

for d in "${deps[@]}"; do
  check_deploy $d
done

section "CHECKING SERVICES"

svcs=( oai-amf oai-smf oai-upf oai-nrf oai-cu oai-du oai-nr-ue oai-udr oai-udm )
for s in "${svcs[@]}"; do
  check_service $s
done

section "CHECK HOSTNAMES / DNS RESOLUTION"

hosts=( oai-amf oai-smf oai-upf oai-nrf oai-cu oai-cu-cp oai-du oai-nr-ue oai-ran )
for h in "${hosts[@]}"; do
   check_dns $h
done

section "CHECK ENDPOINTS"
for s in "${svcs[@]}"; do
   if kubectl get endpoints $s -n $NS >/dev/null 2>&1; then
      ok "Endpoints for $s exist"
   else
      warn "No Endpoints for $s"
   fi
done

section "CHECK CONFIGMAP PLACEHOLDERS (CU-CP / CU-UP / DU)"
check_configmap_placeholders oai-cu-cp-configmap
check_configmap_placeholders oai-cu-up-configmap
check_configmap_placeholders oai-du-configmap

section "CHECK INIT CONTAINERS BLOCKING (ncat waiting...)"

pods=$(kubectl get pods -n $NS -o jsonpath='{.items[*].metadata.name}')
for p in $pods; do
  initlog=$(kubectl logs $p -n $NS -c init --tail=10 2>/dev/null | grep "waiting")
  if [[ ! -z "$initlog" ]]; then
    warn "Pod $p stuck in init:"
    echo "$initlog"
  fi
done

section "VALIDATING CRITICAL LINKS"

echo
echo "CU-CP → AMF (N2 interface):"
check_dns oai-amf

echo
echo "CU-UP → CU-CP (E1 interface):"
check_dns oai-cu-cp
check_service oai-cu

echo
echo "DU → CU-CP (F1 interface):"
check_dns oai-cu

echo
echo "NR-UE → RFSIM:"
check_dns oai-ran

section "REPORT COMPLETED"
echo -e "\e[32mIf any FAIL appears above → That's the cause of DU/CU-UP hang.\e[0m"
