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

