# OAI 5G Split Lab with FlexRIC (Minikube on WSL2)

This repository contains an end-to-end 5G SA lab based on the OpenAirInterface (OAI) 5G Core and split gNB (CU-CP / CU-UP / DU / NR-UE), extended with a near-RT RIC (FlexRIC) and E2 integration.

The lab is designed to run on **Minikube** inside **WSL2 (Ubuntu)** on Windows.  
All core, RAN and RIC components run as Kubernetes workloads in the `oai5g-split` namespace.

## 1. Repository layout (high level)

- `5g-Lab-gnb-split/`
  - `Dockerfile.oai-gnb-flexric` – custom CU-CP image with FlexRIC Service Models (SMs).
  - `configs/` – RAN config files (`cu-cp.conf`, `cu-up.conf`, `du.conf`, `base_rfsim.conf`, etc.).
  - `k8s/` – Kubernetes manifests for RAN and FlexRIC (ConfigMaps, Services, etc.).
  - `oai-cn5g-fed/` – OAI 5G Core Helm charts (with local tweaks).
- `oai-e2-ran/` – RAN / E2 related code and helpers.
- `scripts/`
  - `deploy_all_split_lab.sh` – Phase 2: OAI 5G Core + split gNB (CU-CP / CU-UP / DU / NR-UE).
  - `build_and_deploy_e2_ran_v2.sh` – Build E2-enabled RAN images from OAI and deploy them.
  - `build_custom_cucp_flexric.sh` – Build the custom CU-CP image with FlexRIC SMs and patch the deployment.
  - `enable_flexric_e2.sh` – Deploy FlexRIC, patch CU-CP config (e2_agent + RIC IP + -E), and enable E2.
  - `Network_health.sh` – End-to-end health check for core, RAN and E2/FlexRIC.
- `telco-monitor/` – Optional traffic / monitoring components.
- `get_helm.sh` – Helper script to install Helm.

---

## 2. Prerequisites

### 2.1. Host environment

- Windows 10/11 with:
  - **WSL2** enabled.
  - **Ubuntu** installed in WSL2 (recommended).
- Internet connectivity (to pull OAI images and clone repos).

### 2.2. Inside WSL2 (Ubuntu)

The following tools are required inside WSL:

- `curl`, `git`, `conntrack`, `jq`, `iproute2` (on the host).
- **Docker** (or Docker Desktop with WSL integration).
- **kubectl**
- **Minikube**
- **Helm**

Minimal setup:

```bash
# Update apt
sudo apt-get update && sudo apt-get upgrade -y

# Basic tooling
sudo apt-get install -y \
  curl git conntrack socat jq iproute2

# If using Docker directly inside WSL:
# (skip if you rely on Docker Desktop with WSL integration)
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
# log out / in WSL for the docker group to take effect
