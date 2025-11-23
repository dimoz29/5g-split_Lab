#!/usr/bin/env bash
set -euo pipefail

GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; NC="\e[0m"

echo -e "${GREEN}"
echo "=============================================================="
echo "   OAI E2 RAN Upgrade (CU-CP / DU / CU-UP / NR-UE) - v3"
echo "=============================================================="
echo -e "${NC}"

NAMESPACE="oai5g-split"
LAB_ROOT="$HOME/lab"
HELM_DIR="${LAB_ROOT}/5g-Lab-gnb-split/oai-cn5g-fed"

# Local images (already built)
IMG_GNB="oai-gnb:e2"
IMG_CUUP="oai-cu-up:e2"
IMG_UE="oai-nr-ue:e2"

# ==> Helm releases
REL_CUCP="oai-cu-cp-split"
REL_DU="oai-du-split"
REL_CUUP="oai-cu-up-split"
REL_UE="oai-nr-ue-split"

# ==> Kubernetes deployments (from your pod names)
DEP_CUCP="oai-cu-cp"
DEP_DU="oai-du"
DEP_CUUP="oai-cu-up"
DEP_UE="oai-nr-ue"

echo -e "${YELLOW}Validating environment...${NC}"

for cmd in kubectl helm minikube docker; do
  command -v $cmd >/dev/null || { echo -e "${RED}Missing: $cmd${NC}"; exit 1; }
done

kubectl get ns $NAMESPACE >/dev/null || {
  echo -e "${RED}Namespace ${NAMESPACE} not found.${NC}"
  exit 1
}

echo -e "${GREEN}✔ Environment OK${NC}\n"

echo -e "${YELLOW}Loading images into Minikube...${NC}"
minikube image load "$IMG_GNB"
minikube image load "$IMG_CUUP"
minikube image load "$IMG_UE"
echo -e "${GREEN}✔ Images loaded${NC}\n"

cd "$HELM_DIR"

echo -e "${YELLOW}Upgrading CU-CP...${NC}"
helm upgrade "$REL_CUCP" charts/oai-5g-ran/oai-cu-cp \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-gnb" \
  --set image.tag="e2"

echo -e "${YELLOW}Upgrading DU...${NC}"
helm upgrade "$REL_DU" charts/oai-5g-ran/oai-du \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-gnb" \
  --set image.tag="e2"

echo -e "${YELLOW}Upgrading CU-UP...${NC}"
helm upgrade "$REL_CUUP" charts/oai-5g-ran/oai-cu-up \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-cu-up" \
  --set image.tag="e2"

echo -e "${YELLOW}Upgrading NR-UE...${NC}"
helm upgrade "$REL_UE" charts/oai-5g-ran/oai-nr-ue \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-nr-ue" \
  --set image.tag="e2"

echo -e "${GREEN}✔ Helm upgrade commands executed${NC}\n"

echo -e "${YELLOW}Waiting for rollout to complete...${NC}"
kubectl rollout status deploy/$DEP_CUCP -n $NAMESPACE --timeout=600s || true
kubectl rollout status deploy/$DEP_DU   -n $NAMESPACE --timeout=600s || true
kubectl rollout status deploy/$DEP_CUUP -n $NAMESPACE --timeout=600s || true
kubectl rollout status deploy/$DEP_UE   -n $NAMESPACE --timeout=600s || true

echo -e "${GREEN}"
echo "=============================================================="
echo "            ✔ E2 RAN Upgrade Complete"
echo "=============================================================="
echo -e "${NC}"

kubectl get pods -n $NAMESPACE -o wide | grep -E "cu|du|ue|NAME"

echo
echo -e "${YELLOW}Check E2 logs with:${NC}"
echo "  kubectl logs -n $NAMESPACE deploy/$DEP_CUCP | grep -i e2"
echo "  kubectl logs -n $NAMESPACE deploy/$DEP_DU   | grep -i e2"
echo
echo -e "${GREEN}Done.${NC}"
