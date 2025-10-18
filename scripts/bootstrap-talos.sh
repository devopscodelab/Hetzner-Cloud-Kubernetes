
#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}Talos Cluster Bootstrap${NC}"
echo -e "${GREEN}==================================${NC}"

# Get IPs from Terraform output
cd terraform
CONTROL_PLANE_IP=$(terraform output -raw control_plane_ip)
WORKER_IPS=($(terraform output -json worker_ips | jq -r '.[]'))
cd ..

echo -e "${YELLOW}Control Plane IP: ${CONTROL_PLANE_IP}${NC}"
echo -e "${YELLOW}Worker IPs: ${WORKER_IPS[@]}${NC}"
echo ""

# Step 1: Wait for servers to boot
echo -e "${YELLOW}Step 1: Waiting for servers to boot into Talos (5 minutes)...${NC}"
sleep 300

# Step 2: Generate Talos configs
echo -e "${YELLOW}Step 2: Generating Talos configurations...${NC}"
mkdir -p talos
talosctl gen config talos-k8s https://${CONTROL_PLANE_IP}:6443 \
  --output-dir ./talos \
  --kubernetes-version=v1.28.0

# Step 3: Configure talosctl
echo -e "${YELLOW}Step 3: Configuring talosctl...${NC}"
export TALOSCONFIG=./talos/talosconfig
talosctl config endpoint ${CONTROL_PLANE_IP}
talosctl config node ${CONTROL_PLANE_IP}

# Step 4: Wait for Talos API
echo -e "${YELLOW}Step 4: Waiting for Talos API to be ready...${NC}"
for i in {1..30}; do
  if talosctl version --nodes ${CONTROL_PLANE_IP} 2>/dev/null; then
    echo -e "${GREEN}✓ Talos API is ready!${NC}"
    break
  fi
  echo "Attempt $i/30: Waiting 10 seconds..."
  sleep 10
done

# Step 5: Apply control plane config
echo -e "${YELLOW}Step 5: Applying control plane configuration...${NC}"
talosctl apply-config --insecure \
  --nodes ${CONTROL_PLANE_IP} \
  --file ./talos/controlplane.yaml

# Step 6: Wait and bootstrap etcd
echo -e "${YELLOW}Step 6: Waiting 2 minutes for control plane to initialize...${NC}"
sleep 120

echo -e "${YELLOW}Bootstrapping etcd...${NC}"
talosctl bootstrap --nodes ${CONTROL_PLANE_IP}

# Step 7: Apply worker configs
echo -e "${YELLOW}Step 7: Applying worker configurations...${NC}"
for WORKER_IP in "${WORKER_IPS[@]}"; do
  echo "Configuring worker: ${WORKER_IP}"
  talosctl apply-config --insecure \
    --nodes ${WORKER_IP} \
    --file ./talos/worker.yaml
done

# Step 8: Get kubeconfig
echo -e "${YELLOW}Step 8: Retrieving kubeconfig...${NC}"
sleep 60
talosctl kubeconfig ./kubeconfig --nodes ${CONTROL_PLANE_IP}

# Step 9: Verify cluster
export KUBECONFIG=./kubeconfig
echo -e "${YELLOW}Step 9: Verifying cluster...${NC}"
kubectl get nodes

echo ""
echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}Bootstrap Complete!${NC}"
echo -e "${GREEN}==================================${NC}"
echo ""
echo "Next steps:"
echo "1. export KUBECONFIG=$(pwd)/kubeconfig"
echo "2. kubectl get pods -A"
echo "3. Install applications (Crossplane, Traefik, Cert-Manager)"
