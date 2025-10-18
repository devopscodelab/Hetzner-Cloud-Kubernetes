
#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Talos Kubernetes Deployment${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: terraform is not installed${NC}"
    exit 1
fi

if ! command -v talosctl &> /dev/null; then
    echo -e "${RED}Error: talosctl is not installed${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

if [ -z "$TF_VAR_hcloud_token" ]; then
    echo -e "${RED}Error: TF_VAR_hcloud_token environment variable is not set${NC}"
    echo "Please run: export TF_VAR_hcloud_token='your-token-here'"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites satisfied${NC}"
echo ""

# Change to terraform directory
cd terraform

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Plan deployment
echo -e "${YELLOW}Planning deployment...${NC}"
terraform plan

# Confirm deployment
echo ""
read -p "Do you want to proceed with deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo -e "${RED}Deployment cancelled${NC}"
    exit 0
fi

# Apply Terraform
echo -e "${YELLOW}Deploying infrastructure...${NC}"
terraform apply -auto-approve

# Export kubeconfig
export KUBECONFIG=$(pwd)/../kubeconfig

# Wait for cluster to be ready
echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
sleep 30

# Verify cluster
echo -e "${YELLOW}Verifying cluster...${NC}"
kubectl get nodes

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "Kubeconfig: ${KUBECONFIG}"
echo -e "Control Plane IP: $(terraform output -raw control_plane_ip)"
echo ""
echo -e "Next steps:"
echo -e "1. Configure DNS for your domain"
echo -e "2. Update manifests/cert-manager/cluster-issuer.yaml with your email"
echo -e "3. Deploy example service: kubectl apply -f ../manifests/crossplane/example-service.yaml"
echo ""
