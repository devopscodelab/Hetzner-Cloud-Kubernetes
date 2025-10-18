provider "hcloud" {
  token = var.hcloud_token
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

# Generate Talos configurations locally
resource "null_resource" "talos_config" {
  triggers = {
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ./../talos
      talosctl gen config ${var.cluster_name} https://${hcloud_server.control_plane.ipv4_address}:6443 \
        --output-dir ./../talos \
        --force \
        --kubernetes-version=${var.kubernetes_version}
    EOT
  }

  depends_on = [hcloud_server.control_plane]
}

# Control Plane Node
resource "hcloud_server" "control_plane" {
  name        = "${var.cluster_name}-control-1"
  server_type = var.server_type
  image       = var.base_image
  location    = var.location
  firewall_ids = [hcloud_firewall.cluster_firewall.id]

  user_data = <<-EOT
    #cloud-config
    runcmd:
      - curl -sL https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.11.3/hcloud-amd64.raw.xz | xz -d | dd of=/dev/sda && reboot
  EOT

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.10"
  }

  depends_on = [
    hcloud_network_subnet.private_subnet
  ]

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
  image       = var.base_image
  location    = var.location
  firewall_ids = [hcloud_firewall.cluster_firewall.id]

  user_data = <<-EOT
    #cloud-config
    runcmd:
      - curl -sL https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.11.3/hcloud-amd64.raw.xz | xz -d | dd of=/dev/sda && reboot
  EOT

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.${20 + count.index}"
  }

  depends_on = [
    hcloud_network_subnet.private_subnet
  ]

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

# Bootstrap Talos cluster
resource "null_resource" "talos_bootstrap" {
  triggers = {
    cluster_name = var.cluster_name
    control_plane_id = hcloud_server.control_plane.id
    worker_ids       = join(",", hcloud_server.workers[*].id)
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for Talos OS to boot (much faster with pre-installed image)
      echo "Waiting for Talos OS to boot..."
      sleep 60

      # Configure talosctl
      export TALOSCONFIG=./../talos/talosconfig
      talosctl config endpoint ${hcloud_server.control_plane.ipv4_address}
      talosctl config node ${hcloud_server.control_plane.ipv4_address}

      # Wait for Talos API to be available
      echo "Waiting for Talos API to be ready..."
      for i in {1..30}; do
        if talosctl version --nodes ${hcloud_server.control_plane.ipv4_address} 2>/dev/null; then
          echo "Talos API is ready!"
          break
        fi
        echo "Attempt $i/30: Talos API not ready yet, waiting 10 seconds..."
        sleep 10
      done

      # Apply control plane config
      echo "Applying control plane configuration..."
      talosctl apply-config --insecure \
        --nodes ${hcloud_server.control_plane.ipv4_address} \
        --file ./../talos/controlplane.yaml

      # Wait for control plane to be ready
      echo "Waiting for control plane to initialize..."
      sleep 120

      # Bootstrap etcd
      echo "Bootstrapping etcd..."
      talosctl bootstrap --nodes ${hcloud_server.control_plane.ipv4_address}

      # Apply worker configs
      %{ for idx, worker in hcloud_server.workers ~}
      echo "Configuring worker ${idx + 1}..."
      talosctl apply-config --insecure \
        --nodes ${worker.ipv4_address} \
        --file ./../talos/worker.yaml
      %{ endfor ~}

      # Wait for cluster to stabilize
      echo "Waiting for cluster to stabilize..."
      sleep 60

      # Get kubeconfig
      echo "Retrieving kubeconfig..."
      talosctl kubeconfig ./../kubeconfig --nodes ${hcloud_server.control_plane.ipv4_address}

      echo "Bootstrap complete!"
    EOT
  }

  depends_on = [
    null_resource.talos_config,
    hcloud_server.control_plane,
    hcloud_server.workers
  ]
}