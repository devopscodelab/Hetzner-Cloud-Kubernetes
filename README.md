
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

Before starting, ensure you have the following tools installed:

1. **Terraform** (>= 1.0)
   ```bash
   # Already installed in Replit environment
   terraform version
   ```

2. **talosctl** (Talos CLI)
   ```bash
   curl -sL https://talos.dev/install | sh
   ```

3. **kubectl** (Kubernetes CLI)
   ```bash
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl
   sudo mv kubectl /usr/local/bin/
   ```

4. **Hetzner Cloud API Token**
   - Create an API token in your Hetzner Cloud Console: https://console.hetzner.cloud/
   - Set it as an environment variable (see Deployment Steps)

## Project Structure

```
.
├── terraform/
│   ├── main.tf              # Main Terraform configuration
│   ├── variables.tf         # Input variables
│   ├── outputs.tf          # Output values
│   └── versions.tf         # Provider versions
├── talos/
│   ├── controlplane-userdata.yaml   # Control plane config template
│   └── worker-userdata.yaml         # Worker config template
├── manifests/
│   ├── crossplane/
│   │   ├── install.yaml
│   │   ├── composition.yaml
│   │   └── example-service.yaml
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
export TF_VAR_hcloud_token="your-hetzner-api-token-here"
```

**Note**: TalosOS doesn't use SSH - the cluster is managed entirely through the Talos API, making it more secure than traditional setups.

### Step 2: Initialize and Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Step 3: What Happens During Deployment

1. **Infrastructure Provisioning** (5-10 minutes)
   - Creates Hetzner Cloud servers (1 control plane, 2 workers)
   - Sets up private networking (10.0.0.0/24)
   - Configures firewall rules (only ports 6443, 443, 50000 exposed)

2. **Talos Bootstrap** (automatic via cloud-init)
   - Generates Talos machine configurations
   - Bootstraps the control plane
   - Joins worker nodes to the cluster

3. **Kubernetes Stack** (ready after bootstrap)
   - Kubernetes v1.28.0 installed
   - Ready for Crossplane, Traefik, and Cert-Manager deployment

### Step 4: Access Your Cluster

After deployment completes, the outputs will show:

```bash
# Set kubeconfig path
export KUBECONFIG=./../kubeconfig

# Verify cluster
kubectl get nodes
```

Expected output:
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

✅ **No SSH Access**: TalosOS has no SSH by design - all management via secure API
✅ **Immutable OS**: TalosOS is read-only and declaratively configured
✅ **Minimal Attack Surface**: No package manager, no shell access
✅ **Secrets Management**: Token via environment variable only
✅ **Network Segmentation**: Private network for inter-node communication
✅ **RBAC**: Kubernetes role-based access control enabled
✅ **Encrypted API**: Talos API uses mutual TLS
✅ **Firewall**: Only essential ports exposed (6443, 443, 50000)

## Firewall Configuration

The following ports are exposed:

- **6443**: Kubernetes API (from anywhere)
- **443**: HTTPS ingress (from anywhere)
- **50000**: Talos API (from anywhere)
- **ICMP**: Internal network only (10.0.0.0/16)

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

### Issue: Terraform plan fails with token error

Ensure your token is exactly 64 characters and set correctly:
```bash
export TF_VAR_hcloud_token="your-64-character-token"
echo ${#TF_VAR_hcloud_token}  # Should output: 64
```

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
kubectl logs -n traefik -l app=traefik
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
terraform destroy
```

⚠️ **Warning**: This will permanently delete all infrastructure and data.

## Cost Estimation

**Monthly costs** (as of 2024):
- 1x cx22 control plane: ~€5.83/month
- 2x cx22 workers: ~€11.66/month
- **Total**: ~€17.49/month + minimal network/volume costs

## Next Steps

1. Configure your domain DNS to point to the Traefik LoadBalancer IP
2. Update `manifests/cert-manager/cluster-issuer.yaml` with your email
3. Deploy Crossplane: `kubectl apply -f manifests/crossplane/install.yaml`
4. Deploy Traefik: `kubectl apply -f manifests/traefik/values.yaml`
5. Deploy Cert-Manager and apply cluster issuer
6. Deploy your applications using the WebService CRD

## Key Differences from Traditional K8s Setup

1. **No SSH Required**: TalosOS manages everything through its API
2. **Immutable Infrastructure**: OS cannot be modified at runtime
3. **Declarative Configuration**: All changes via machine configs
4. **Minimal Dependencies**: Only Hetzner Cloud token needed
5. **Enhanced Security**: Reduced attack surface with no shell access

## Support & Contributing

- **Talos Documentation**: https://www.talos.dev/
- **Hetzner Cloud Docs**: https://docs.hetzner.com/cloud/
- **Crossplane Docs**: https://crossplane.io/docs/

## License

MIT License - Feel free to use and modify for your needs.
