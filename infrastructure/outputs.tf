# ==========================================================
# INFRASTRUCTURE OUTPUTS (CONFIGURATION DATA)
# ==========================================================

# --- 1. ACCESS & MANAGEMENT ---

# This provides the exact command to SSH into your cluster.
output "master_ssh_command" {
  description = "Copy and paste this into your terminal to log in to the Master node."
  value       = "ssh -i YourKeyPair.pem ubuntu@${aws_eip.master_eip.public_ip}"
}

# The Public IP for your Jenkins and Monitoring dashboards.
output "master_public_ip" {
  description = "The static public IP of your management node."
  value       = aws_eip.master_eip.public_ip
}


# --- 2. MOLECULAR APP CONFIGURATION ---

# This is the "Nervous System" URL. 
# Your 6 Workers need this to communicate with the NATS broker on the Master.
output "nats_transporter_url" {
  description = "Use this for the 'TRANSPORTER' env variable in your Real-World services."
  value       = "nats://${aws_instance.master.private_ip}:4222"
}

# This is the "Vault" connection string.
# Your database-heavy microservices (like Users or Articles) need this.
output "mongodb_connection_uri" {
  description = "Use this for the 'MONGO_URI' env variable in your workers."
  value       = "mongodb://${aws_instance.mongodb.private_ip}:27017/realworld"
}

# The Public URL to access your finished RealWorld App in the browser.
output "app_api_gateway_url" {
  description = "The entry point for the Molecular API Gateway."
  value       = "http://${aws_eip.master_eip.public_ip}:3000"
}


# --- 3. CLUSTER NETWORKING ---

# List of Private IPs for all 6 workers. 
# You will need these to join the workers to the K3s cluster.
output "worker_nodes_private_ips" {
  description = "List of internal IPs for the 6 worker nodes."
  value       = aws_instance.workers[*].private_ip
}

# The internal IP of the MongoDB node.
output "mongodb_private_ip" {
  description = "The internal IP of the database node."
  value       = aws_instance.mongodb.private_ip
}