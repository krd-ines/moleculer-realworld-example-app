output "master_node_details" {
  description = "Access information for the Master Node"
  value = {
    public_ip   = aws_instance.master_node.public_ip
    ssh_login   = "ssh -i vockey.pem ubuntu@${aws_instance.master_node.public_ip}"
    jenkins_url = "http://${aws_instance.master_node.public_ip}:8080"
  }
}

output "monitoring_links" {
  description = "Monitoring and Debugging Links"
  value = {
    grafana_url    = "http://${aws_instance.grafana_server.public_ip}:3000"
    prometheus_url = "http://${aws_instance.grafana_server.public_ip}:9090"
    # IMPORTANT: Use this to check if nodes are "UP" or "DOWN"
    prometheus_targets = "http://${aws_instance.grafana_server.public_ip}:9090/targets"
  }
}

output "application_url" {
  description = "Direct link to the deployed application (K8s NodePort)"
  value       = "http://${aws_instance.master_node.public_ip}:32448/"
}

output "infrastructure_private_ips" {
  description = "Internal network map"
  value = {
    database_ip = aws_instance.db_instance.private_ip
    worker_ips  = aws_instance.app_services[*].private_ip
  }
}