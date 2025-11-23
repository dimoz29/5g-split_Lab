#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# OAI 5G RAN (E2-enabled) Deploy Script
# Upgrades CU-CP, DU, CU-UP, NR-UE images to local E2-enabled images
# Namespace: oai5g-split
# Charts: ~/lab/5g-Lab-gnb-split/oai-cn5g-fed/charts/oai-5g-ran/
###############################################################################

# Colors for readability
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
NC="\e[0m"

echo -e "${GREEN}"
echo "=================================================================="
echo "   OAI E2-enabled RAN Deployment Script (CU-CP / DU / CU-UP / UE) "
echo "=================================================================="
echo -e "${NC}"

###############################################################################
# Paths & Vars
###############################################################################

LAB_ROOT="$HOME/lab"
NAMESPACE="oai5g-split"
HELM_DIR="${LAB_ROOT}/5g-Lab-gnb-split/oai-cn5g-fed"

# E2 Enabled Images (host docker → minikube)
IMG_GNB="oai-gnb:e2"
IMG_CUUP="oai-cu-up:e2"
IMG_UE="oai-nr-ue:e2"

# Helm Release names
REL_CUCP="oai-cu-cp"
REL_DU="oai-du"
REL_CUUP="oai-cu-up"
REL_UE="oai-nr-ue"

###############################################################################
# 1. Validation
###############################################################################
echo -e "${YELLOW}Checking environment...${NC}"

for cmd in kubectl helm minikube docker; do
  command -v $cmd >/dev/null || {
    echo -e "${RED}❌ Missing command: $cmd${NC}"
    exit 1
  }
done

kubectl get ns $NAMESPACE >/dev/null || {
  echo -e "${RED}❌ Namespace $NAMESPACE does not exist.${NC}"
  exit 1
}

if [ ! -d "$HELM_DIR/charts/oai-5g-ran" ]; then
  echo -e "${RED}❌ Helm charts not found at $HELM_DIR${NC}"
  exit 1
fi

echo -e "${GREEN}✔ Environment OK${NC}"

###############################################################################
# 2. Load local E2 images into Minikube
###############################################################################
echo -e "${YELLOW}Loading E2 images into Minikube...${NC}"

minikube image load "$IMG_GNB"
minikube image load "$IMG_CUUP"
minikube image load "$IMG_UE"

echo -e "${GREEN}✔ Images loaded into Minikube${NC}"

###############################################################################
# 3. HELM UPGRADE
###############################################################################
cd "$HELM_DIR"

echo -e "${YELLOW}Upgrading CU-CP to ${IMG_GNB}...${NC}"
helm upgrade "$REL_CUCP" charts/oai-5g-ran/oai-cu-cp \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-gnb" \
  --set image.tag="e2"

echo -e "${YELLOW}Upgrading DU to ${IMG_GNB}...${NC}"
helm upgrade "$REL_DU" charts/oai-5g-ran/oai-du \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-gnb" \
  --set image.tag="e2"

echo -e "${YELLOW}Upgrading CU-UP to ${IMG_CUUP}...${NC}"
helm upgrade "$REL_CUUP" charts/oai-5g-ran/oai-cu-up \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-cu-up" \
  --set image.tag="e2"

echo -e "${YELLOW}Upgrading NR-UE to ${IMG_UE}...${NC}"
helm upgrade "$REL_UE" charts/oai-5g-ran/oai-nr-ue \
  --namespace "$NAMESPACE" \
  --reuse-values \
  --set image.repository="oai-nr-ue" \
  --set image.tag="e2"

echo -e "${GREEN}✔ Helm upgrades applied${NC}"

###############################################################################
# 4. Wait for Rollout
###############################################################################
echo -e "${YELLOW}Waiting for pods to become Ready...${NC}"

kubectl rollout status deployment/"$REL_CUCP" -n "$NAMESPACE" --timeout=600s || true
kubectl rollout status deployment/"$REL_DU"   -n "$NAMESPACE" --timeout=600s || true
kubectl rollout status deployment/"$REL_CUUP" -n "$NAMESPACE" --timeout=600s || true
kubectl rollout status deployment/"$REL_UE"   -n "$NAMESPACE" --timeout=600s || true

###############################################################################
# 5. Summary
###############################################################################

echo -e "${GREEN}"
echo "=================================================================="
echo "           ✔ E2 RAN DEPLOY COMPLETE"
echo "=================================================================="
echo -e "${NC}"

echo -e "${YELLOW}Active RAN Pods:${NC}"
kubectl get pods -n "$NAMESPACE" -o wide | grep -E "cu|du|ue|NAME"
echo

echo -e "${YELLOW}Check E2 initialization logs with:${NC}"
echo "  kubectl logs -n $NAMESPACE deployment/$REL_CUCP | grep -i e2"
echo "  kubectl logs -n $NAMESPACE deployment/$REL_DU   | grep -i e2"
echo
echo -e "${GREEN}Done.${NC}"
