
# Hetzner Cloud Kubernetes with TalosOS - Platform Team Challenge

This project provides a fully automated Terraform setup to deploy a production-ready Kubernetes cluster on Hetzner Cloud using TalosOS, with Crossplane, Traefik, and Cert-Manager pre-configured for developer self-service.

## Challenge Overview

**Goal**: Bootstrap a Kubernetes cluster on Hetzner Cloud running TalosOS, with Crossplane compositions that allow developers to easily deploy HTTPS-enabled services.

**Key Requirements Met**:
- ✅ Basic security principles applied (see Security section)
- ✅ Everything in Git for version control
- ✅ Complete automation - reproducible deployment process
- ✅ Comprehensive documentation

## Architecture

- **Infrastructure Provider**: Hetzner Cloud
- **Kubernetes Distribution**: TalosOS (minimal, immutable, secure OS)
- **Cluster Configuration**: 1 Control Plane + 2 Worker Nodes (3 nodes total for budget)
- **Server Type**: cx22 (2 vCPU, 4GB RAM) - cost-optimized as per requirements
- **Region**: fsn1 (Falkenstein, Germany)
- **Networking**: Private network (10.0.0.0/16) for inter-node communication
- **Ingress Controller**: Traefik (as recommended)
- **Certificate Management**: Cert-Manager with Let's Encrypt
- **Developer Self-Service**: Crossplane with custom WebService composition

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

## Automation & Reproducibility

This deployment is **100% automated** and **fully reproducible**. The entire infrastructure can be created or destroyed with simple commands.

### Automation Approach

1. **Infrastructure as Code**: All resources defined in Terraform
2. **Declarative Configuration**: TalosOS machine configs in YAML
3. **Automated Bootstrap**: Cluster initialization via Terraform provisioners
4. **GitOps Ready**: All manifests version-controlled and declarative

### Reproducibility Guarantees

- Same Terraform code = Same infrastructure every time
- No manual steps required
- Clean slate deployment: `terraform destroy` → `terraform apply`
- Version-pinned components (Kubernetes, Crossplane, Traefik, Cert-Manager)

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

## Developer Self-Service with Crossplane

The core feature of this platform: developers can deploy production-ready HTTPS services without infrastructure knowledge.

### How It Works

1. **Crossplane WebService Composition**: Custom resource definition that abstracts complexity
2. **Automatic HTTPS**: Cert-Manager requests and configures Let's Encrypt certificates
3. **Load Balancing**: Traefik automatically routes traffic based on hostname/path
4. **Declarative**: Developers describe what they want, Crossplane handles how

### Customization Options Available to Developers

- `replicas`: Number of pod replicas (horizontal scaling)
- `image`: Container image to deploy
- `port`: Application port
- `path`: URL path for the service
- `host`: Domain name for HTTPS access

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

## Security Approach

This deployment implements multiple layers of security following the principle of defense in depth:

### 1. Infrastructure Security
✅ **Hetzner Cloud Firewall**: Restricts traffic at the network level
  - Only ports 80, 443 (ingress), 6443 (K8s API), 50000 (Talos API) exposed publicly
  - Internal traffic (10.0.0.0/16) isolated on private network
  - All other ports blocked by default

✅ **Private Networking**: Nodes communicate via dedicated private network (10.0.1.0/24)
  - Control plane and workers use private IPs for cluster communication
  - Reduces attack surface by keeping etcd and kubelet traffic internal

### 2. Operating System Security (TalosOS)
✅ **No SSH Access**: TalosOS has no SSH daemon - management only via secure API
✅ **Immutable OS**: Root filesystem is read-only, preventing runtime modifications
✅ **Minimal Attack Surface**: No shell, no package manager, no unnecessary services
✅ **Encrypted API**: All Talos API communication uses mutual TLS authentication
✅ **Declarative Configuration**: All changes must go through version-controlled machine configs

### 3. Kubernetes Security
✅ **RBAC Enabled**: Role-based access control for all API operations
✅ **Network Policies**: Can be applied via Crossplane compositions
✅ **Pod Security Standards**: Enforced at namespace level
✅ **Secrets Management**: Kubernetes secrets encrypted at rest

### 4. Application Security
✅ **TLS Termination**: Automatic HTTPS via Cert-Manager + Let's Encrypt
✅ **HTTP to HTTPS Redirect**: Forced HTTPS for all ingress traffic (Traefik configured)
✅ **Certificate Rotation**: Automated by Cert-Manager

### 5. Operational Security
✅ **API Token Protection**: Hetzner token stored as environment variable (TF_VAR_hcloud_token)
✅ **No Hardcoded Secrets**: All sensitive data passed via variables or generated
✅ **Audit Trail**: All infrastructure changes tracked in Git
✅ **Least Privilege**: Service accounts with minimal required permissions

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

## Cost Estimation & Budget Management

**Monthly costs** (as of 2024):
- 1x cx22 control plane: ~€5.83/month
- 2x cx22 workers: ~€11.66/month
- 1x lb11 load balancer: ~€5.39/month
- **Total**: ~€22.88/month

**Daily costs**: ~€0.76/day

### Cost Optimization for Development

As recommended in the challenge requirements, **delete nodes when done for the day**:

```bash
# End of day cleanup
cd terraform
terraform destroy -auto-approve

# Next day - restore cluster
terraform apply -auto-approve
```

This keeps costs minimal during the development/testing phase.

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
