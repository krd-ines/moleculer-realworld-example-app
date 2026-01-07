variable "aws_region" {
  description = "The AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "The specific AZ to deploy into"
  type        = string
  default     = "us-east-1a"
}

variable "iam_instance_profile_name" {
  description = "Name of the existing IAM Instance Profile (e.g. LabInstanceProfile)"
  type        = string
  default     = "LabInstanceProfile"
}

# --- Networking CIDRs ---
variable "vpc_cidr" {
  description = "CIDR for the whole VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for Master Node Subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_app_cidr" {
  description = "CIDR for Service Nodes Subnet (Privet net 1)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_db_cidr" {
  description = "CIDR for DB Node Subnet (Privet net 2)"
  type        = string
  default     = "10.0.3.0/24"
}

# --- Application Ports (Specific to your Stack) ---

variable "http_port" {
  description = "Port for HTTP traffic (Gateway)"
  type        = number
  default     = 80
}

variable "jenkins_port" {
  description = "Port for Jenkins UI"
  type        = number
  default     = 8080
}

variable "k8s_port" {
  description = "Port for Kubernetes API (K3s) - Communication Master <-> Services"
  type        = number
  default     = 6443
}


variable "mongodb_port" {
  description = "Port for MongoDB"
  type        = number
  default     = 27017
}

# --- Instance Configuration ---

variable "master_instance_type" {
  description = "Master node: t3.medium, ubuntu"
  type        = string
  default     = "t3.medium"
}

variable "app_instance_type" {
  description = "Service nodes: t3.small, ubuntu"
  type        = string
  default     = "t3.small"
}

variable "dockerhub_password" {
  description = "The password or access token for Docker Hub"
  type        = string
  sensitive   = true
}

variable "db_instance_type" {
  description = "DB node: t3.medium, ubuntu"
  type        = string
  default     = "t3.medium"
}

variable "app_instance_count" {
  description = "Number of Service Nodes (1-6)"
  type        = number
  default     = 3
}
# --- Security / Access Control ---

variable "admin_cidr" {
  description = "IP Address allowed to SSH (Port 22). Default is open, but you should change this!"
  type        = string
  default     = "0.0.0.0/0"
}

variable "web_access_cidr" {
  description = "IP addresses allowed to access Jenkins/HTTP (Port 80/8080)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "anywhere_cidr" {
  description = "Standard CIDR for 'Anywhere' (Used for Egress/Outbound traffic)"
  type        = string
  default     = "0.0.0.0/0"
}