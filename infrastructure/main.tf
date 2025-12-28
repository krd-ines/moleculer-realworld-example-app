provider "aws" {
  region = var.aws_region
}

# --- 1. Data Sources ---
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

data "aws_iam_instance_profile" "lab_profile" {
  name = var.iam_instance_profile_name
}

# --- 2. Network ---
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "Project-VPC" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "Project-IGW" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true
  tags = { Name = "Public-Subnet-Master" }
}

resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_app_cidr
  availability_zone = var.availability_zone
  tags = { Name = "Private-Subnet-Services" }
}

resource "aws_subnet" "private_db" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_db_cidr
  availability_zone = var.availability_zone
  tags = { Name = "Private-Subnet-DB" }
}

# --- 3. Network ACLs ---
resource "aws_network_acl" "public_acl" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id]

  # Allow all Inbound/Outbound for simplicity in Public Subnet
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  tags = { Name = "Public-NACL" }
}

resource "aws_network_acl" "app_acl" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_app.id]

  # Allow Internal VPC Traffic + Return Traffic
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0" # Trusting broadly for Lab ease (Master NAT needs 0.0.0.0/0 return)
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  tags = { Name = "App-NACL" }
}

resource "aws_network_acl" "db_acl" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_db.id]

  # Allow Inbound from VPC (Workers) and Reply Traffic
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }
  # Allow Ephemeral ports from Internet (via NAT)
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound to Anywhere (For Updates via Master NAT)
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  tags = { Name = "DB-NACL" }
}

# --- 4. Security Groups ---

resource "aws_security_group" "master_sg" {
  name   = "master-sg"
  vpc_id = aws_vpc.main.id

  # Admin Access (SSH, HTTP, Jenkins)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.web_access_cidr]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.web_access_cidr]
  }

  # Allow K3s API and NAT Traffic from Internal VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound: Allow All
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "services_sg" {
  name   = "services-sg"
  vpc_id = aws_vpc.main.id

  # Allow All Internal Traffic (Worker-to-Worker communication)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound: Allow All
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  # Allow MongoDB (27017) from VPC
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow SSH from VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound: Allow All (Updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 5. Instances ---

# MASTER NODE (The Router, K3s Server & Jenkins Server)
resource "aws_instance" "master_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.public.id
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.master_sg.id]
  key_name               = "vockey"

  # --- CRITICAL: Allow Traffic Passing ---
  source_dest_check      = false

  # --- CRITICAL: Configure NAT, Install K3s & Install Jenkins ---
  user_data = <<-EOF
              #!/bin/bash
              # 1. Enable IP Forwarding (Router Mode)
              sysctl -w net.ipv4.ip_forward=1
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

              # 2. Enable Masquerading (NAT)
              iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              apt-get update && apt-get install -y iptables-persistent

              # 3. Install K3s Server
              curl -sfL https://get.k3s.io | K3S_TOKEN=mysecretpassword sh -

              # --- JENKINS INSTALLATION START ---

              # 4. Install Java (Required for Jenkins)
              apt-get install -y openjdk-17-jre

              # 5. Install Jenkins
              curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee \
                /usr/share/keyrings/jenkins-keyring.asc > /dev/null
              echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
                https://pkg.jenkins.io/debian-stable binary/ | tee \
                /etc/apt/sources.list.d/jenkins.list > /dev/null
              apt-get update
              apt-get install -y jenkins

              # 6. Start Jenkins
              systemctl start jenkins
              systemctl enable jenkins

              # 7. Add Jenkins to Docker Group (So it can build images)
              # Note: K3s installs 'containerd', but for building images we might need standard docker or buildkit.
              # For simplicity in this lab, we will install standard docker for Jenkins to use.
              apt-get install -y docker.io
              usermod -aG docker jenkins
              chmod 666 /var/run/docker.sock

              # 8. Configure Kubeconfig for Jenkins (So it can deploy)
              # Wait for K3s to finish initializing
              sleep 30
              mkdir -p /var/lib/jenkins/.kube
              cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
              chown jenkins:jenkins /var/lib/jenkins/.kube/config
              chmod 600 /var/lib/jenkins/.kube/config

              # 9. Restart Jenkins to apply group changes
              systemctl restart jenkins

              # --- JENKINS INSTALLATION END ---

              echo "Master Node Ready"
              EOF

  tags = { Name = "Master-Node" }
}

# WORKER NODES (The K3s Agents)
resource "aws_instance" "app_services" {
  count                  = var.app_instance_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private_app.id
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.services_sg.id]
  key_name               = "vockey"

  depends_on = [aws_instance.master_node]

  # --- CRITICAL: Join the Master automatically ---
  user_data = <<-EOF
              #!/bin/bash
              # 1. Wait a moment for Master to be ready
              sleep 60

              # 2. Install K3s Agent pointing to Master IP
              curl -sfL https://get.k3s.io | K3S_URL=https://${aws_instance.master_node.private_ip}:6443 K3S_TOKEN=mysecretpassword sh -
              EOF

  tags = { Name = "Service-Worker-${count.index + 1}" }
}

# DATABASE INSTANCE (MongoDB)
resource "aws_instance" "db_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.private_db.id
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = "vockey"

  depends_on = [aws_instance.master_node]

  # --- CRITICAL: Install Mongo & Allow Remote Access ---
  user_data = <<-EOF
              #!/bin/bash
              # 1. Update and Install MongoDB (Uses NAT to reach internet)
              apt-get update
              apt-get install -y mongodb

              # 2. Configure Mongo to listen to 0.0.0.0 (All IPs)
              # Default is 127.0.0.1, we change it so workers can connect
              sed -i 's/bind_ip = 127.0.0.1/bind_ip = 0.0.0.0/' /etc/mongodb.conf

              # 3. Restart Service
              systemctl restart mongodb
              EOF

  tags = { Name = "DB-Instance" }
}

# --- 6. Route Tables ---

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "Public-Route-Table" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# PRIVATE ROUTE TABLE (The "Signpost" to the Master)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  # --- CRITICAL: Route Internet Traffic to Master Node ---
  route {
    cidr_block           = "0.0.0.0/0"
    instance_id          = aws_instance.master_node.id
  }

  tags = { Name = "Private-Route-Table" }
}

resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_db_assoc" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private_rt.id
}

