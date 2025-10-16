
# Hetzner Cloud Kubernetes with TalosOS - Terraform Automation

This project provides a fully automated Terraform setup to deploy a production-ready Kubernetes cluster on Hetzner Cloud using TalosOS, with Crossplane, Traefik, and Cert-Manager pre-configured.

## Architecture

- **Infrastructure Provider**: Hetzner Cloud
- **Kubernetes Distribution**: TalosOS (minimal, immutable OS)
- **Cluster Configuration**: 1 Control Plane + 2 Worker Nodes
- **Server Type**: cx22 (2 vCPU, 4GB RAM)
- **Region**: fsn1 (Falkenstein, Germany)
- **Networking**: Private network between nodes
- **Ingress**: Traefik
- **Certificate Management**: Cert-Manager
- **GitOps/IaC Extension**: Crossplane

## Prerequisites

Before starting, ensure you have the following tools installed on your local machine:

1. **Terraform** (>= 1.0)
   ```bash
   # Install Terraform
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. **talosctl** (Talos CLI)
   ```bash
   curl -sL https://talos.dev/install | sh
   ```

3. **kubectl** (Kubernetes CLI)
   ```bash
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```

4. **Hetzner Cloud API Token**
   - Create an API token in your Hetzner Cloud Console: https://console.hetzner.cloud/
   - Export it as an environment variable:
   ```bash
   export HCLOUD_TOKEN="your-api-token-here"
   ```

## Project Structure

```
.
├── terraform/
│   ├── main.tf              # Main Terraform configuration
│   ├── variables.tf         # Input variables
│   ├── outputs.tf          # Output values
│   └── versions.tf         # Provider versions
├── talos/
│   ├── controlplane.yaml   # Generated control plane config
│   └── worker.yaml         # Generated worker config
├── manifests/
│   ├── crossplane/
│   │   ├── install.yaml
│   │   └── composition.yaml
│   ├── traefik/
│   │   └── values.yaml
│   └── cert-manager/
│       └── cluster-issuer.yaml
├── scripts/
│   └── deploy.sh           # Automated deployment script
└── README.md               # This file
```

## Deployment Steps

### Step 1: Set Environment Variables

```bash
export HCLOUD_TOKEN="your-hetzner-api-token"
export CLUSTER_NAME="talos-k8s"
export EMAIL="your-email@example.com"  # For Let's Encrypt certificates
```

### Step 2: One-Command Deployment

Run the automated deployment script:

```bash
./scripts/deploy.sh
```

**OR** manually execute:

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### Step 3: What Happens During Deployment

1. **Infrastructure Provisioning** (5-10 minutes)
   - Creates Hetzner Cloud servers (1 control plane, 2 workers)
   - Sets up private networking
   - Configures firewall rules

2. **Talos Bootstrap** (3-5 minutes)
   - Generates Talos machine configurations
   - Bootstraps the control plane
   - Joins worker nodes to the cluster

3. **Kubernetes Stack Installation** (5-10 minutes)
   - Installs Crossplane
   - Deploys Traefik ingress controller
   - Configures Cert-Manager with Let's Encrypt

### Step 4: Access Your Cluster

After deployment completes, retrieve the kubeconfig:

```bash
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

You should see output similar to:
```
NAME                STATUS   ROLES           AGE   VERSION
talos-control-1     Ready    control-plane   5m    v1.28.0
talos-worker-1      Ready    <none>          4m    v1.28.0
talos-worker-2      Ready    <none>          4m    v1.28.0
```

## Using Crossplane for Developer Self-Service

This setup includes a Crossplane composition that allows developers to deploy HTTPS-enabled services with a simple YAML manifest.

### Example: Deploy a Web Service

Create a file `my-service.yaml`:

```yaml
apiVersion: platform.example.com/v1alpha1
kind: WebService
metadata:
  name: my-awesome-app
spec:
  replicas: 3
  image: nginx:latest
  port: 80
  path: /my-app
  host: my-app.yourdomain.com
```

Apply it:

```bash
kubectl apply -f my-service.yaml
```

This will automatically:
- Create a Deployment with the specified replicas
- Create a Service
- Create an Ingress with Traefik
- Request and configure an SSL certificate via Cert-Manager

## Security Features

✅ **SSH Disabled**: TalosOS has no SSH access by design
✅ **Immutable OS**: TalosOS is read-only and declaratively configured
✅ **Secrets Management**: All sensitive data via environment variables
✅ **Network Segmentation**: Private network for inter-node communication
✅ **RBAC**: Kubernetes role-based access control enabled
✅ **Encrypted API**: Talos API uses mutual TLS

## Customization

### Change Server Type

Edit `terraform/variables.tf`:
```hcl
variable "server_type" {
  default = "cx32"  # Upgrade to 4 vCPU, 8GB RAM
}
```

### Change Region

Edit `terraform/variables.tf`:
```hcl
variable "location" {
  default = "nbg1"  # Use Nuremberg instead of Falkenstein
}
```

### Add More Workers

Edit `terraform/variables.tf`:
```hcl
variable "worker_count" {
  default = 3  # Increase to 3 workers
}
```

## Troubleshooting

### Issue: Talos bootstrap fails

```bash
# Check Talos node status
talosctl -n <node-ip> health
talosctl -n <node-ip> logs
```

### Issue: Nodes not joining cluster

```bash
# Verify network connectivity
talosctl -n <node-ip> get members
```

### Issue: Ingress not working

```bash
# Check Traefik status
kubectl get pods -n traefik
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
```

### Issue: Certificates not issuing

```bash
# Check Cert-Manager
kubectl get certificaterequests -A
kubectl describe certificate <cert-name> -n <namespace>
```

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy -auto-approve
```

⚠️ **Warning**: This will permanently delete all infrastructure and data.

## Cost Estimation

**Monthly costs** (as of 2024):
- 1x cx22 control plane: ~€5.83/month
- 2x cx22 workers: ~€11.66/month
- **Total**: ~€17.49/month + minimal network/volume costs

## Next Steps

1. Configure your domain DNS to point to the Traefik LoadBalancer IP
2. Update the Crossplane composition with your domain
3. Deploy your applications using the WebService CRD
4. Set up monitoring with Prometheus/Grafana
5. Configure backup solutions for etcd

## Support & Contributing

- **Issues**: Report issues in the project repository
- **Documentation**: https://www.talos.dev/
- **Hetzner Cloud**: https://docs.hetzner.com/cloud/

## License

MIT License - Feel free to use and modify for your needs.
