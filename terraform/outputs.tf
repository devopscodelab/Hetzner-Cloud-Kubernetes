
output "control_plane_ip" {
  description = "Public IP of the control plane node"
  value       = hcloud_server.control_plane.ipv4_address
}

output "worker_ips" {
  description = "Public IPs of worker nodes"
  value       = hcloud_server.workers[*].ipv4_address
}

output "load_balancer_ip" {
  description = "Public IP of the Kubernetes API load balancer"
  value       = hcloud_load_balancer.k8s_api.ipv4
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = "${path.module}/../kubeconfig"
}

output "talosconfig_path" {
  description = "Path to the talosconfig file"
  value       = "${path.module}/../talos/talosconfig"
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    Deployment complete! Next steps:

    1. Set kubeconfig:
       export KUBECONFIG=${path.module}/../kubeconfig

    2. Verify cluster:
       kubectl get nodes

    3. Check cluster status:
       kubectl get pods -A

    4. Deploy applications:
       - Crossplane: kubectl apply -f manifests/crossplane/install.yaml
       - Traefik: (Helm chart needed)
       - Cert-Manager: (Helm chart needed)

    Control Plane IP: ${hcloud_server.control_plane.ipv4_address}
    Worker IPs: ${join(", ", hcloud_server.workers[*].ipv4_address)}
  EOT
}
