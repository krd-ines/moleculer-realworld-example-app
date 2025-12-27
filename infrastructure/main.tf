terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}





# --- STEP 1: NETWORK FOUNDATION ---
# This VPC is the private "container" for your entire project.
resource "aws_vpc" "realworld_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "Real-World-Project-VPC" }
}

# The Public Subnet hosts the Master node so YOU can reach it from the internet.
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.realworld_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

# Private Subnet A holds your 6 Worker nodes (The App Tier).
resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.realworld_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
}

# Private Subnet B holds ONLY the MongoDB (The Data Tier). 
# Extreme isolation for security.
resource "aws_subnet" "private_db" {
  vpc_id            = aws_vpc.realworld_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
}







# --- STEP 2: INTERNET ACCESS ---
# The Gateway allows the Master node to talk to the internet.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.realworld_vpc.id
}

# The Elastic IP (EIP) gives your Master a static address that never changes.
resource "aws_eip" "master_eip" {
  instance = aws_instance.master.id
  domain   = "vpc"
}

# --- STEP 3: SECURITY GROUPS (FIREWALLS) ---

# ==========================================================
# SECURITY GROUPS (THE VIRTUAL FIREWALLS)
# ==========================================================

# --- 1. MASTER NODE SECURITY GROUP ---
# This group manages management access (SSH), CI/CD (Jenkins), 
# and the cluster's control plane (K3s API & NATS).
resource "aws_security_group" "master_sg" {
  name        = "realworld-master-sg"
  description = "Management and API Gateway"
  vpc_id      = aws_vpc.realworld_vpc.id

  # SSH: For manual administration.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to you.
  }

  # realworld API GATEWAY: The public entry point for your RealWorld app.
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to users.
  }

  # JENKINS UI: For your CI/CD pipeline management.
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

#   # K3s API SERVER: Allows worker nodes to register with the Master.
#   ingress {
#     from_port       = 6443
#     to_port         = 6443
#     protocol        = "tcp"
#     security_groups = [aws_security_group.worker_sg.id] # Only Workers can join.
#   }

#   # NATS TRANSPORTER: realworld microservices use this to find each other.
#   ingress {
#     from_port       = 4222
#     to_port         = 4222
#     protocol        = "tcp"
#     security_groups = [aws_security_group.worker_sg.id] # Restricted to internal apps.
#   }

#   # EGRESS: Allows the Master to download Docker images and OS updates.
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
}

# --- 2. WORKER NODE SECURITY GROUP ---
# These nodes run your actual microservices. They need to talk to 
# each other and the Master.
resource "aws_security_group" "worker_sg" {
  name        = "realworld-worker-sg"
  description = "Microservices execution and K3s networking"
  vpc_id      = aws_vpc.realworld_vpc.id

  # K3s INTERNAL NETWORKING (Flannel VXLAN):
  # Required for Pod-to-Pod communication across different nodes.
  ingress {
    from_port = 8472
    to_port   = 8472
    protocol  = "udp"
    self      = true # Allows workers to talk to other workers.
  }

#   # KUBELET METRICS: Allows the Master (Grafana/Prometheus) to pull performance data.
#   ingress {
#     from_port       = 10250
#     to_port         = 10250
#     protocol        = "tcp"
#     security_groups = [aws_security_group.master_sg.id]
#   }

  # EGRESS: Allows workers to reach NATS (on Master) and MongoDB.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Add the "Bridge" Rule: Allow Workers to talk to Master (NATS/K3s)
resource "aws_security_group_rule" "workers_to_master_nats" {
  type                     = "ingress"
  from_port                = 4222
  to_port                  = 4222
  protocol                 = "tcp"
  security_group_id        = aws_security_group.master_sg.id
  source_security_group_id = aws_security_group.worker_sg.id
}

# 4. Add the "Bridge" Rule: Allow Master to talk to Workers (Metrics)
resource "aws_security_group_rule" "master_to_workers_metrics" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.worker_sg.id
  source_security_group_id = aws_security_group.master_sg.id
}

# --- 3. DATABASE SECURITY GROUP ---
# The most restricted group. Only the app workers can talk to MongoDB.
resource "aws_security_group" "db_sg" {
  name        = "realworld-db-sg"
  description = "Isolated MongoDB Tier"
  vpc_id      = aws_vpc.realworld_vpc.id

  # MONGODB PORT: Only accessible by the Worker nodes running the app logic.
  ingress {
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.worker_sg.id] # NO Public Access.
  }

  # EGRESS: Usually restricted, but allows DB to pull patches if needed.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}









# --- STEP 4: COMPUTE NODES ---
# Master Node: The "Brain." Runs K3s, Jenkins, and NATS.
resource "aws_instance" "master" {
  ami           = "ami-0e2c8ccd9e036d13a" 
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.master_sg.id]
}

# 6 Worker Nodes: The "Workers." Each runs 1 realworld microservice.
resource "aws_instance" "workers" {
  count         = 6
  ami           = "ami-0e2c8ccd9e036d13a"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_app.id
  vpc_security_group_ids = [aws_security_group.worker_sg.id]
}

# MongoDB Node: The "Vault." Stores all the RealWorld app data.
resource "aws_instance" "mongodb" {
  ami           = "ami-0e2c8ccd9e036d13a"
  instance_type = "t3.small"
  subnet_id     = aws_subnet.private_db.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
}


resource "aws_network_acl" "public_nacl" {
  vpc_id     = aws_vpc.realworld_vpc.id
  subnet_ids = [aws_subnet.public.id]

  # --- INBOUND ---
  ingress { # SSH
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
    protocol   = "tcp"
  }
  ingress { # Real-World API Gateway
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 3000
    to_port    = 3000
    protocol   = "tcp"
  }
  ingress { # Jenkins
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 8080
    to_port    = 8080
    protocol   = "tcp"
  }
  ingress { # Ephemeral ports (Required for responses from Workers/Internet)
    rule_no    = 140
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
    protocol   = "tcp"
  }

  # --- OUTBOUND ---
  egress { # All traffic out (updates, talking to workers)
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
  }
}

resource "aws_network_acl" "app_nacl" {
  vpc_id     = aws_vpc.realworld_vpc.id
  subnet_ids = [aws_subnet.private_app.id]

  ingress { # Internal VPC Traffic (K3s, NATS, etc.)
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.realworld_vpc.cidr_block
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
  }
  
  ingress { # Ephemeral ports for external responses (OS updates)
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
    protocol   = "tcp"
  }

  egress {
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
  }
}

resource "aws_network_acl" "db_nacl" {
  vpc_id     = aws_vpc.realworld_vpc.id
  subnet_ids = [aws_subnet.private_db.id]

  ingress { # ONLY Allow MongoDB port from the App Subnet
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_subnet.private_app.cidr_block
    from_port  = 27017
    to_port    = 27017
    protocol   = "tcp"
  }

  egress { # Respond to App Subnet
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_subnet.private_app.cidr_block
    from_port  = 1024
    to_port    = 65535
    protocol   = "tcp"
  }
}