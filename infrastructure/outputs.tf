
output "master_node_details" {
  description = "Access information for the Master Node"
  value = {
    ip          = aws_instance.master_node.public_ip
    ssh_login   = "ssh -i vockey.pem ubuntu@${aws_instance.master_node.public_ip}"
    jenkins_url = "http://${aws_instance.master_node.public_ip}:8080"
    prometheus_url = "http://${aws_instance.master_node.public_ip}:30090"
    grafana_url = "http://${aws_instance.master_node.public_ip}:30030"
  }
}

output "application_access_instruction" {
  description = "How to access your app"
  value       = "Check 'kubectl get svc' for the port, then visit http://${aws_instance.master_node.public_ip}:<PORT>"
}

output "worker_nodes_private_ips" {
  description = "Private IPs of the Service Nodes"
  value       = aws_instance.app_services[*].private_ip
}

output "database_private_ip" {
  description = "Private IP of the Database"
  value       = aws_instance.db_instance.private_ip
}