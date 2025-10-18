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

# Note: Talos bootstrap is done manually after infrastructure is created
# See scripts/bootstrap-talos.sh for the bootstrap process