````markdown
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
````

Install `kubectl` (example for latest stable):

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s \
  https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

Install Minikube:

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
```

Install Helm (or use the bundled `get_helm.sh`):

```bash
cd ~/lab
chmod +x get_helm.sh
./get_helm.sh
```

> **Note**: Make sure Docker is running and accessible from WSL (e.g. `docker ps` works).

---

## 3. Start Minikube (WSL2)

From inside WSL2 (Ubuntu):

```bash
minikube start \
  --cpus=6 \
  --memory=12000 \
  --disk-size=40g \
  --driver=docker \
  --network-plugin=cni \
  --cni=flannel
```

Check status:

```bash
minikube status
kubectl get nodes
```

---

## 4. Clone this repository

Inside WSL:

```bash
mkdir -p ~/lab
cd ~/lab

git clone https://github.com/dimoz29/5g-split_Lab.git
cd 5g-split_Lab

# make all scripts executable
cd scripts
chmod +x *.sh
cd ..
```

From now on, all paths in this README assume:

```bash
LAB_ROOT=~/lab
REPO_DIR=~/lab/5g-split_Lab
```

---

## 5. Phase 2 – Deploy OAI 5G Core + split gNB

This step deploys:

* OAI 5G SA Core (NRF, AMF, SMF, UPF, UDM, UDR, AUSF, LMF, MySQL, traffic-server).
* Split gNB:

  * CU-CP
  * CU-UP
  * DU
  * NR-UE

All in namespace: `oai5g-split`.

From inside the repo:

```bash
cd ~/lab/5g-split_Lab

./scripts/deploy_all_split_lab.sh
```

This script will:

* Create the `oai5g-split` namespace.
* Use the local `oai-cn5g-fed` Helm charts to deploy the 5G Core.
* Deploy CU-CP, CU-UP, DU and NR-UE with the default OAI images.

Check:

```bash
kubectl get pods -n oai5g-split
```

You should see core and RAN pods in `Running` state (NR-UE may restart while attaching).

---

## 6. Phase 2.5 – Build E2-enabled RAN images (from OAI)

Next, build the E2-capable RAN images from the upstream OAI repository and update the running RAN components to use them.

```bash
cd ~/lab/5g-split_Lab

./scripts/build_and_deploy_e2_ran_v2.sh
```

This script will:

* Clone/update the OAI `openairinterface5g` repo (branch `develop`).
* Build E2-enabled images:

  * `oai-gnb:e2`
  * `oai-du:e2`
  * `oai-cu-up:e2`
  * `oai-nr-ue:e2`
* Load these images into Minikube.
* Run `helm upgrade` for the RAN Helm releases in the `oai5g-split` namespace.

Check images and pods:

```bash
kubectl get deploy -n oai5g-split \
  -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

At this point, the RAN is E2-capable at build level, but E2 is not yet enabled in CU-CP config or connected to FlexRIC.

---

## 7. Phase 3 – Build custom CU-CP with FlexRIC SMs

This step builds the **custom CU-CP image** with FlexRIC Service Models and patches the CU-CP deployment to use it.

```bash
cd ~/lab/5g-split_Lab

./scripts/build_custom_cucp_flexric.sh
```

What this does:

* Builds `oai-gnb:2024.w32-flexric` using `5g-Lab-gnb-split/Dockerfile.oai-gnb-flexric`.
* Loads the image into Minikube.
* Patches `deployment/oai-cu-cp` (namespace `oai5g-split`) to use this custom image.
* Verifies that FlexRIC SM libraries are present in `/usr/local/lib/flexric` inside the CU-CP pod.

You can manually verify:

```bash
kubectl get deploy oai-cu-cp -n oai5g-split -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
# should print: oai-gnb:2024.w32-flexric
```

---

## 8. Phase 3 – Enable FlexRIC + E2 integration

Finally, enable E2 coupling between CU-CP and FlexRIC.

```bash
cd ~/lab/5g-split_Lab

./scripts/enable_flexric_e2.sh
```

This script performs:

1. **Deploy / update FlexRIC**

   * Applies `oai-flexric.yaml` manifests (ConfigMap, Deployment, Service).
   * Waits for `deployment/oai-flexric` to become ready.
   * Captures the FlexRIC pod name and IP.

2. **Install `iproute2` inside the FlexRIC pod** (if possible)

   * Makes tools like `ss` available inside the container (useful for debugging).
   * Not strictly required for functionality, but helps health checks.

3. **Patch CU-CP ConfigMap (`oai-cu-cp-configmap`)**

   * Backs up the current ConfigMap to a timestamped YAML file.
   * Ensures an `e2_agent` block exists in `cucp.conf`.
   * Sets `near_ric_ip_addr` to the current FlexRIC **Pod IP**.
   * Ensures `e2_port = 36421`, `sm_dir = "/usr/local/lib/flexric/"`, and proper E2AP/KPM versions.

4. **Patch CU-CP environment for E2**

   * Updates `USE_ADDITIONAL_OPTIONS` to include `-E`, e.g.:

     ```text
     --sa -E --log_config.global_log_options level,nocolor,time
     ```

   * This makes `nr-softmodem` start with E2 enabled.

5. **Restart CU-CP and verify SCTP 36421**

   * Performs `kubectl rollout restart` on `deployment/oai-cu-cp`.
   * Checks for an SCTP socket from CU-CP to the RIC on port 36421 using `ss`.

If everything is correct, you should see an established SCTP association:

```bash
kubectl exec -it -n oai5g-split \
  $(kubectl get pods -n oai5g-split -o name | grep oai-cu-cp | head -1) -- \
  ss -na | grep 36421
```

Example:

```text
ESTAB  0  0  10.244.x.y%eth0:3xxxx  10.244.a.b:36421
```

This indicates that CU-CP ↔ FlexRIC E2 control-plane is **up and running**.

---

## 9. Health check

Use the bundled network health script to validate the full stack:

```bash
cd ~/lab/5g-split_Lab/scripts

./Network_health.sh
```

The script checks:

* Kubernetes health and namespace reachability.
* OAI 5G Core deployments.
* RAN components (CU-CP / CU-UP / DU / UE).
* FlexRIC deployment.
* Basic K8s-level connectivity (ICMP where available).
* End-to-end UE → Internet connectivity.
* E2 / FlexRIC connectivity (SCTP 36421).
* Basic protocol hints in logs (NGAP, PFCP, GTP-U, F1, E1, E2).

Some warnings (especially about ping or logs) are “soft” and may be expected depending on image contents and logging levels. The key E2 indicator is:

* `E2 SCTP CU-CP → RIC on 36421 is ESTABLISHED`

---

## 10. Reset / redeploy

If you want to reset the split lab and redeploy from scratch:

```bash
# Delete the namespace (this removes all core/RAN/RIC resources)
kubectl delete namespace oai5g-split

# (Optionally) restart Minikube
minikube delete
minikube start ...    # with the same parameters as before

# Then repeat:
# 1) deploy_all_split_lab.sh
# 2) build_and_deploy_e2_ran_v2.sh
# 3) build_custom_cucp_flexric.sh
# 4) enable_flexric_e2.sh
```

---

## 11. Notes

* This lab is meant for experimentation and learning with OAI + FlexRIC + E2 on a single-node Minikube cluster.
* The custom CU-CP image `oai-gnb:2024.w32-flexric` is **not** stored in the repo; it is always built locally from `Dockerfile.oai-gnb-flexric`.
* FlexRIC is currently based on the official image `oaisoftwarealliance/oai-flexric:develop`, with optional in-pod installation of `iproute2` for tooling.

```
::contentReference[oaicite:0]{index=0}
```
