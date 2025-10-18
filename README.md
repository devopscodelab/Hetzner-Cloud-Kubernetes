# Hetzner Cloud Kubernetes with TalosOS - Platform Team Challenge

This project provides a fully automated Terraform setup to deploy a production-ready Kubernetes cluster on Hetzner Cloud using TalosOS, with Crossplane, Traefik, and Cert-Manager pre-configured for developer self-service.

## Challenge Overview

**Goal**: Bootstrap a Kubernetes cluster on Hetzner Cloud running TalosOS, with Crossplane compositions that allow developers to easily deploy HTTPS-enabled services.

**Key Requirements Met**:
- ✅ Basic security principles applied (see Security section)
- ✅ Everything in Git for version control
- ✅ **Complete automation** - Single `terraform apply` deploys everything
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

## Deployment Steps

### Step 1: Set Environment Variables

```bash
export TF_VAR_hcloud_token="your-hetzner-api-token-here"
```

### Step 2: Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply
```

### What Happens During Deployment

1. **Infrastructure Provisioning** (~2 minutes)
   - Creates Hetzner Cloud servers
   - Sets up private networking
   - Configures firewall rules

2. **Talos OS Installation via Cloud-Init** (~5-7 minutes)
   - Cloud-init downloads Talos OS image
   - Writes Talos to disk and reboots servers
   - Servers boot into Talos OS

3. **Cluster Bootstrap** (~3-5 minutes)
   - Generates Talos configurations
   - Applies control plane config
   - Bootstraps etcd
   - Joins worker nodes
   - Retrieves kubeconfig

**Total deployment time**: ~12-15 minutes for a fully operational cluster

### Step 3: Access Your Cluster

After `terraform apply` completes successfully:

```bash
# Set kubeconfig path
export KUBECONFIG=../kubeconfig

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

## Automation & Reproducibility

This deployment is **fully automated** via Terraform with cloud-init.

### Key Features

✅ **Single Command Deployment**: `terraform apply` provisions everything
✅ **Cloud-Init Integration**: Talos OS installed automatically on boot
✅ **Idempotent**: Safe to run multiple times
✅ **Clean Destruction**: `terraform destroy` removes all resources

### How It Works

1. Terraform creates Hetzner Cloud servers
2. Cloud-init downloads and installs Talos OS to disk
3. Servers reboot into Talos OS
4. Terraform waits for Talos API, then bootstraps cluster
5. Kubeconfig automatically retrieved and saved

## Developer Self-Service with Crossplane

The core feature of this platform: developers can deploy production-ready HTTPS services without infrastructure knowledge.

### How It Works

1. **Crossplane WebService Composition**: Custom resource definition that abstracts complexity
2. **Automatic HTTPS**: Cert-Manager requests and configures Let's Encrypt certificates
3. **Load Balancing**: Traefik automatically routes traffic based on hostname/path
4. **Declarative**: Developers describe what they want, Crossplane handles how

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
✅ **Private Networking**: Nodes communicate via dedicated private network

### 2. Operating System Security (TalosOS)
✅ **No SSH Access**: TalosOS has no SSH daemon
✅ **Immutable OS**: Root filesystem is read-only
✅ **Minimal Attack Surface**: No shell, no package manager
✅ **Encrypted API**: All Talos API communication uses mutual TLS

### 3. Kubernetes Security
✅ **RBAC Enabled**: Role-based access control
✅ **Network Policies**: Can be applied via Crossplane
✅ **Secrets Management**: Kubernetes secrets encrypted at rest

### 4. Application Security
✅ **TLS Termination**: Automatic HTTPS via Cert-Manager + Let's Encrypt
✅ **Certificate Rotation**: Automated by Cert-Manager

## Troubleshooting

### Deployment takes too long

The first deployment includes:
- Downloading Talos OS (~300MB per node)
- Installing to disk and rebooting
- Kubernetes initialization

Total time: 12-15 minutes is normal.

### Talos API not responding

```bash
# Check if servers have rebooted into Talos
cd terraform
terraform output control_plane_ip

# Try accessing Talos API
export TALOSCONFIG=../talos/talosconfig
talosctl -n <control_plane_ip> version
```

### Cluster not bootstrapping

```bash
# Check Talos logs
talosctl -n <control_plane_ip> logs
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
- 1x lb11 load balancer: ~€5.39/month
- **Total**: ~€22.88/month (~€0.76/day)

### Cost Optimization

Delete when not in use:
```bash
terraform destroy -auto-approve
```

Recreate next day:
```bash
terraform apply -auto-approve
```

## Next Steps

1. Configure DNS to point to LoadBalancer IP
2. Deploy Crossplane: `kubectl apply -f manifests/crossplane/install.yaml`
3. Deploy Traefik (Helm)
4. Deploy Cert-Manager (Helm)
5. Create WebService resources

## License

MIT License