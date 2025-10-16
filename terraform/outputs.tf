
output "control_plane_ip" {
  description = "Public IP of the control plane node"
  value       = hcloud_server.control_plane.ipv4_address
}

output "worker_ips" {
  description = "Public IPs of worker nodes"
  value       = [for worker in hcloud_server.workers : worker.ipv4_address]
}

output "load_balancer_ip" {
  description = "IP of the Kubernetes API load balancer"
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

output "cluster_endpoint" {
  description = "Kubernetes cluster endpoint"
  value       = "https://${hcloud_server.control_plane.ipv4_address}:6443"
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    
    ✅ Cluster deployed successfully!
    
    Next steps:
    
    1. Set your kubeconfig:
       export KUBECONFIG=${path.module}/../kubeconfig
    
    2. Verify cluster:
       kubectl get nodes
    
    3. Check installed components:
       kubectl get pods -A
    
    4. Configure DNS for your domain to point to Traefik LoadBalancer IP
    
    5. Deploy a sample service:
       kubectl apply -f manifests/crossplane/example-service.yaml
    
  EOT
}
