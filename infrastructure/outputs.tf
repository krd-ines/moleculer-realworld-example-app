output "master_public_ip" {
  description = "Public IP of the Master Node (Jenkins/K8s)"
  value       = aws_instance.master_node.public_ip
}

output "service_private_ips" {
  description = "Private IPs of the Service Nodes"
  value       = aws_instance.app_services[*].private_ip
}

output "db_private_ip" {
  description = "Private IP of the Database"
  value       = aws_instance.db_instance.private_ip
}