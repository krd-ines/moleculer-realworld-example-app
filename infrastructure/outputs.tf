

output "master_node_details" {
  description = "Access information for the Master Node"
  value = {
    ip          = aws_instance.master_node.public_ip
    ssh_login   = "ssh -i vockey.pem ubuntu@${aws_instance.master_node.public_ip}"
    jenkins_url = "http://${aws_instance.master_node.public_ip}:8080"
  }
}

output "application_url" {
  description = "Direct link to the deployed application"
  value       = "http://${aws_instance.master_node.public_ip}:32448/"
}

output "grafana_dashboard_url" {
  description = "Direct link to the Grafana Monitoring Dashboard"
  value       = "http://${aws_instance.grafana_server.public_ip}:3000"
}

output "worker_nodes_private_ips" {
  description = "Private IPs of the Service Nodes"
  value       = aws_instance.app_services[*].private_ip
}

output "database_private_ip" {
  description = "Private IP of the Database"
  value       = aws_instance.db_instance.private_ip
}
output "grafana_url" {
  value = "http://${aws_instance.grafana_server.public_ip}:3000"
}

