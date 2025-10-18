provider "hcloud" {
  token = var.hcloud_token
}

# SSH Key for emergency access (though Talos doesn't use SSH)
resource "hcloud_ssh_key" "default" {
  name       = "${var.cluster_name}-key"
  public_key = var.ssh_public_key
}

# Private Network for internal communication
resource "hcloud_network" "private_network" {
  name     = "${var.cluster_name}-network"
  ip_range = var.network_ip_range
}

resource "hcloud_network_subnet" "private_subnet" {
  network_id   = hcloud_network.private_network.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_ip_range
}

# Firewall for cluster security
resource "hcloud_firewall" "cluster_firewall" {
  name = "${var.cluster_name}-firewall"

  # Allow Kubernetes API from anywhere
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow Talos API
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "50000"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow HTTP/HTTPS for ingress
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow all internal traffic
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "any"
    source_ips = [var.network_ip_range]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "any"
    source_ips = [var.network_ip_range]
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = [var.network_ip_range]
  }
}

# Control Plane Node
resource "hcloud_server" "control_plane" {
  name        = "${var.cluster_name}-control-1"
  server_type = var.server_type
  image       = "ubuntu-22.04"  # Will be replaced by Talos
  location    = var.location
  firewall_ids = [hcloud_firewall.cluster_firewall.id]

  user_data = templatefile("${path.module}/../talos/controlplane-userdata.yaml", {
    cluster_name = var.cluster_name
    node_ip      = "10.0.1.10"
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.10"
  }

  depends_on = [hcloud_network_subnet.private_subnet]

  labels = {
    role    = "control-plane"
    cluster = var.cluster_name
  }
}

# Worker Nodes
resource "hcloud_server" "workers" {
  count       = var.worker_count
  name        = "${var.cluster_name}-worker-${count.index + 1}"
  server_type = var.server_type
  image       = "ubuntu-22.04"  # Will be replaced by Talos
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.cluster_firewall.id]

  user_data = templatefile("${path.module}/../talos/worker-userdata.yaml", {
    cluster_name     = var.cluster_name
    node_ip          = "10.0.1.${20 + count.index}"
    control_plane_ip = hcloud_server.control_plane.ipv4_address
  })

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.${20 + count.index}"
  }

  depends_on = [hcloud_network_subnet.private_subnet]

  labels = {
    role    = "worker"
    cluster = var.cluster_name
  }
}

# Load Balancer for Kubernetes API
resource "hcloud_load_balancer" "k8s_api" {
  name               = "${var.cluster_name}-api-lb"
  load_balancer_type = "lb11"
  location           = var.location

  labels = {
    cluster = var.cluster_name
    type    = "api"
  }
}

resource "hcloud_load_balancer_network" "k8s_api" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  network_id       = hcloud_network.private_network.id
  ip               = "10.0.1.254"

  depends_on = [hcloud_network_subnet.private_subnet]
}

resource "hcloud_load_balancer_target" "k8s_api_target" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  server_id        = hcloud_server.control_plane.id
}

resource "hcloud_load_balancer_service" "k8s_api_service" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443
}

# Generate Talos configuration
resource "null_resource" "talos_config" {
  triggers = {
    control_plane_ip = hcloud_server.control_plane.ipv4_address
  }

  provisioner "local-exec" {
    command = <<-EOT
      talosctl gen config ${var.cluster_name} https://${hcloud_server.control_plane.ipv4_address}:6443 \
        --output-dir ${path.module}/../talos \
        --with-secrets ${path.module}/../talos/secrets.yaml \
        --kubernetes-version=${var.kubernetes_version}
    EOT
  }

  depends_on = [hcloud_server.control_plane]
}

# Bootstrap Talos cluster
resource "null_resource" "talos_bootstrap" {
  triggers = {
    control_plane_ip = hcloud_server.control_plane.ipv4_address
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure talosctl
      talosctl config endpoint ${hcloud_server.control_plane.ipv4_address}
      talosctl config node ${hcloud_server.control_plane.ipv4_address}

      # Apply control plane config
      talosctl apply-config --insecure \
        --nodes ${hcloud_server.control_plane.ipv4_address} \
        --file ${path.module}/../talos/controlplane.yaml

      # Wait for control plane to be ready
      sleep 120

      # Bootstrap etcd
      talosctl bootstrap --nodes ${hcloud_server.control_plane.ipv4_address}

      # Apply worker configs
      %{for idx, worker in hcloud_server.workers~}
      talosctl apply-config --insecure \
        --nodes ${worker.ipv4_address} \
        --file ${path.module}/../talos/worker.yaml
      %{endfor~}

      # Get kubeconfig
      talosctl kubeconfig ${path.module}/../kubeconfig --nodes ${hcloud_server.control_plane.ipv4_address}
    EOT
  }

  depends_on = [null_resource.talos_config, hcloud_server.workers]
}

# Install Crossplane
resource "null_resource" "install_crossplane" {
  triggers = {
    cluster_id = null_resource.talos_bootstrap.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/../kubeconfig

      # Wait for cluster to be ready
      kubectl wait --for=condition=Ready nodes --all --timeout=300s

      # Install Crossplane
      kubectl create namespace crossplane-system || true
      kubectl apply -f ${path.module}/../manifests/crossplane/install.yaml

      # Wait for Crossplane to be ready
      kubectl wait --for=condition=Available deployment/crossplane -n crossplane-system --timeout=300s

      # Install Crossplane compositions
      kubectl apply -f ${path.module}/../manifests/crossplane/composition.yaml
    EOT
  }

  depends_on = [null_resource.talos_bootstrap]
}

# Install Traefik
resource "null_resource" "install_traefik" {
  triggers = {
    cluster_id = null_resource.talos_bootstrap.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/../kubeconfig

      # Install Traefik
      kubectl create namespace traefik || true
      kubectl apply -f ${path.module}/../manifests/traefik/values.yaml
    EOT
  }

  depends_on = [null_resource.talos_bootstrap]
}

# Install Cert-Manager
resource "null_resource" "install_cert_manager" {
  triggers = {
    cluster_id = null_resource.talos_bootstrap.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${path.module}/../kubeconfig

      # Install Cert-Manager
      kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

      # Wait for Cert-Manager to be ready
      kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s

      # Install ClusterIssuer
      kubectl apply -f ${path.module}/../manifests/cert-manager/cluster-issuer.yaml
    EOT
  }

  depends_on = [null_resource.talos_bootstrap]
}