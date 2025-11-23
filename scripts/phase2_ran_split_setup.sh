#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Phase 2 RAN Split Lab (CU-CP / CU-UP / DU) – Skeleton Setup
# - Δημιουργεί νέο folder: 5g-Lab-gnb-split
# - Κάνει clone το openairinterface5g (develop)
# - Ετοιμάζει βασικά config & Kubernetes YAML skeletons
# - ΔΕΝ κάνει kubectl apply (μόνο προετοιμάζει αρχεία)
###############################################################################

LAB_ROOT="${HOME}/lab"
LAB_DIR="${LAB_ROOT}/5g-Lab-gnb-split"
REPO_URL="https://github.com/OPENAIRINTERFACE/openairinterface5g.git"
REPO_DIR="${LAB_DIR}/openairinterface5g"

CONFIGS_DIR="${LAB_DIR}/configs"
K8S_DIR="${LAB_DIR}/k8s"

# RFSIM example config (θα το χρησιμοποιήσουμε σαν βάση)
RFSIM_CONF_SRC_REL="ci-scripts/conf_files/gnb.sa.band78.24prb.rfsim.conf"

echo "=== [1] Δημιουργία βασικού φακέλου lab: ${LAB_DIR} ==="
mkdir -p "${LAB_DIR}"
mkdir -p "${CONFIGS_DIR}"
mkdir -p "${K8S_DIR}"

echo "=== [2] Έλεγχος/clone του openairinterface5g (develop) ==="
if [ -d "${REPO_DIR}/.git" ]; then
  echo "Repo υπάρχει ήδη, κάνω git fetch/pull..."
  cd "${REPO_DIR}"
  git fetch origin
  git checkout develop
  git pull --rebase
else
  cd "${LAB_DIR}"
  git clone --branch develop "${REPO_URL}"
  cd "${REPO_DIR}"
fi

echo "Τρέχον repo: $(pwd)"

echo "=== [3] Προετοιμασία βασικών config (rfsim) ==="
if [ -f "${REPO_DIR}/${RFSIM_CONF_SRC_REL}" ]; then
  cp "${REPO_DIR}/${RFSIM_CONF_SRC_REL}" "${CONFIGS_DIR}/base_rfsim.conf"
  echo "  -> Αντέγραψα ${RFSIM_CONF_SRC_REL} σε configs/base_rfsim.conf"
else
  echo "  !! WARNING: Δεν βρήκα ${RFSIM_CONF_SRC_REL} μέσα στο repo."
  echo "     Θα δημιουργήσω placeholder configs, θα χρειαστεί χειροκίνητη ρύθμιση."
  touch "${CONFIGS_DIR}/base_rfsim.conf"
fi

# Δημιουργία απλών placeholders για CU-CP / CU-UP / DU configs
for role in cu-cp cu-up du; do
  CONF_FILE="${CONFIGS_DIR}/${role}.conf"
  if [ ! -f "${CONF_FILE}" ]; then
    cat > "${CONF_FILE}" <<EOF
#############################################
# ${role}.conf - placeholder
# Βάση: configs/base_rfsim.conf
# TODO:
#  - Ρύθμισε PLMN, TAC, AMF/UPF IP/hostnames
#  - Ενεργοποίησε E1 / F1 σύμφωνa με E1-design.md / F1-design.md
#  - Ρύθμισε RAN_FUNCTION_MODE = ${role^^} (σύμφωνα με OAI docs)
#############################################

# ΠΡΟΣΩΡΙΝΑ: include από base_rfsim.conf (λογική, όχι πραγματικό include)
# Αντιγράψε τις σχετικές παραμέτρους από base_rfsim.conf
EOF
    echo "  -> Δημιούργησα placeholder config: ${CONF_FILE}"
  fi
done

echo "=== [4] Δημιουργία Kubernetes YAML skeletons στο ${K8S_DIR} ==="

###############################################################################
# ΣΗΜΕΙΩΣΗ:
# - Namespace: oai5g  (μπορείς να το αλλάξεις σε oai5g-split αν θες isolation)
# - Image: oaisoftwarealliance/oai-gnb:develop  (generic gNB/CU/DU image)
#   Το mode (CU-CP / CU-UP / DU) καθορίζεται απ' το config/args.
###############################################################################

NAMESPACE="oai5g-split"
GNB_IMAGE="oaisoftwarealliance/oai-gnb:develop"

########################
# CU-CP Deployment
########################
cat > "${K8S_DIR}/oai-cu-cp-deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oai-cu-cp
  namespace: ${NAMESPACE}
  labels:
    app: oai-cu-cp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oai-cu-cp
  template:
    metadata:
      labels:
        app: oai-cu-cp
    spec:
      containers:
        - name: cu-cp
          image: ${GNB_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "Starting OAI CU-CP (Phase 2 split)..."
              # TODO: Ρύθμισε τα σωστά options για CU-CP mode
              # π.χ. ./nr-softmodem -O /config/cu-cp.conf --sa --rfsim --e1cp
              tail -f /dev/null
          volumeMounts:
            - name: cu-cp-conf
              mountPath: /config
      volumes:
        - name: cu-cp-conf
          hostPath:
            path: ${CONFIGS_DIR}
            type: Directory
EOF

########################
# CU-UP Deployment
########################
cat > "${K8S_DIR}/oai-cu-up-deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oai-cu-up
  namespace: ${NAMESPACE}
  labels:
    app: oai-cu-up
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oai-cu-up
  template:
    metadata:
      labels:
        app: oai-cu-up
    spec:
      containers:
        - name: cu-up
          image: ${GNB_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "Starting OAI CU-UP (Phase 2 split)..."
              # TODO: Ρύθμισε τα σωστά options για CU-UP mode
              # π.χ. ./nr-softmodem -O /config/cu-up.conf --sa --rfsim --e1up
              tail -f /dev/null
          volumeMounts:
            - name: cu-up-conf
              mountPath: /config
      volumes:
        - name: cu-up-conf
          hostPath:
            path: ${CONFIGS_DIR}
            type: Directory
EOF

########################
# DU Deployment
########################
cat > "${K8S_DIR}/oai-du-deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oai-du
  namespace: ${NAMESPACE}
  labels:
    app: oai-du
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oai-du
  template:
    metadata:
      labels:
        app: oai-du
    spec:
      containers:
        - name: du
          image: ${GNB_IMAGE}
          imagePullPolicy: IfNotPresent
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "Starting OAI DU (Phase 2 split)..."
              # TODO: Ρύθμισε τα σωστά options για DU mode
              # π.χ. ./nr-softmodem -O /config/du.conf --sa --rfsim --du
              tail -f /dev/null
          volumeMounts:
            - name: du-conf
              mountPath: /config
      volumes:
        - name: du-conf
          hostPath:
            path: ${CONFIGS_DIR}
            type: Directory
EOF

########################
# Services skeleton (N2, N3, E1, F1)
########################
cat > "${K8S_DIR}/oai-ran-services.yaml" <<EOF
apiVersion: v1
kind: List
items:
  # N2: CU-CP <-> AMF
  - apiVersion: v1
    kind: Service
    metadata:
      name: oai-cu-cp-n2
      namespace: ${NAMESPACE}
    spec:
      type: ClusterIP
      selector:
        app: oai-cu-cp
      ports:
        - name: n2
          port: 38412
          protocol: SCTP

  # N3: CU-UP <-> UPF
  - apiVersion: v1
    kind: Service
    metadata:
      name: oai-cu-up-n3
      namespace: ${NAMESPACE}
    spec:
      type: ClusterIP
      selector:
        app: oai-cu-up
      ports:
        - name: n3
          port: 2152
          protocol: UDP

  # E1-C: CU-CP <-> CU-UP
  - apiVersion: v1
    kind: Service
    metadata:
      name: oai-cu-cp-e1c
      namespace: ${NAMESPACE}
    spec:
      type: ClusterIP
      selector:
        app: oai-cu-cp
      ports:
        - name: e1c
          port: 38492
          protocol: SCTP

  # E1-U: CU-UP <-> CU-CP
  - apiVersion: v1
    kind: Service
    metadata:
      name: oai-cu-up-e1u
      namespace: ${NAMESPACE}
    spec:
      type: ClusterIP
      selector:
        app: oai-cu-up
      ports:
        - name: e1u
          port: 38493
          protocol: SCTP

  # F1-C: CU-CP <-> DU
  - apiVersion: v1
    kind: Service
    metadata:
      name: oai-du-f1c
      namespace: ${NAMESPACE}
    spec:
      type: ClusterIP
      selector:
        app: oai-du
      ports:
        - name: f1c
          port: 38472
          protocol: SCTP

  # F1-U: CU-UP <-> DU
  - apiVersion: v1
    kind: Service
    metadata:
      name: oai-du-f1u
      namespace: ${NAMESPACE}
    spec:
      type: ClusterIP
      selector:
        app: oai-du
      ports:
        - name: f1u
          port: 2153
          protocol: UDP
EOF

echo "=== [5] Δημιουργία README για το νέο lab ==="
cat > "${LAB_DIR}/README.md" <<EOF
# 5g-Lab-gnb-split (Phase 2 RAN Split Skeleton)

Αυτός ο φάκελος περιέχει:
- Clone του openairinterface5g (branch: develop)
- Βασικά rfsim config templates: configs/*.conf
- Kubernetes YAML skeletons για:
  - CU-CP (oai-cu-cp)
  - CU-UP (oai-cu-up)
  - DU (oai-du)
  - Services (N2, N3, E1-C, E1-U, F1-C, F1-U)

## Σημαντικό:
- ΚΑΝΕΝΑ yaml ΔΕΝ έχει γίνει apply στο cluster.
- Πρέπει πρώτα να ρυθμίσεις:
  - Τα configs (configs/cu-cp.conf, cu-up.conf, du.conf)
  - Τα command args στο κάθε Deployment (nr-softmodem options)
  - Να βεβαιωθείς ότι δείχνουν σωστά στον AMF/UPF του core (namespace oai5g)

## Πως θα κάνεις apply (όταν είσαι έτοιμος):

  # Προαιρετικά: άλλαξε namespace στο YAML αν θέλεις isolation (π.χ. oai5g-split)
  # Μετά:

  kubectl apply -f k8s/oai-cu-cp-deployment.yaml
  kubectl apply -f k8s/oai-cu-up-deployment.yaml
  kubectl apply -f k8s/oai-du-deployment.yaml
  kubectl apply -f k8s/oai-ran-services.yaml

EOF

echo ""
echo "=================================================================="
echo "✔ Ολοκληρώθηκε το skeleton setup για Phase 2 RAN split."
echo "  Folder: ${LAB_DIR}"
echo ""
echo "Περιεχόμενα:"
echo "  - ${REPO_DIR}      : openairinterface5g (develop)"
echo "  - ${CONFIGS_DIR}   : base_rfsim.conf, cu-cp.conf, cu-up.conf, du.conf"
echo "  - ${K8S_DIR}       : YAMLs για CU-CP / CU-UP / DU + services"
echo ""
echo "Τώρα μπορείς να ανοίξεις τα αρχεία:"
echo "  - ${CONFIGS_DIR}/*.conf"
echo "  - ${K8S_DIR}/*.yaml"
echo "και να τα προσαρμόσεις πριν τα κάνεις apply."
echo "=================================================================="
