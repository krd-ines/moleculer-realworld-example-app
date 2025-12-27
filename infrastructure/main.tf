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
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 8080
  }
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
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
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.public_subnet_cidr
    from_port  = 0
    to_port    = 65535
  }
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.private_subnet_db_cidr
    from_port  = 1024
    to_port    = 65535
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
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.private_subnet_app_cidr
    from_port  = 27017
    to_port    = 27017
  }
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 22
    to_port    = 22
  }
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.private_subnet_app_cidr
    from_port  = 1024
    to_port    = 65535
  }
  tags = { Name = "DB-NACL" }
}

# --- 4. Security Groups (FIXED: No Cycles) ---

# A. Master SG
resource "aws_security_group" "master_sg" {
  name   = "master-sg"
  vpc_id = aws_vpc.main.id

  # Internet Ingress
  ingress {
    from_port   = var.jenkins_port
    to_port     = var.jenkins_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# B. Services SG
resource "aws_security_group" "services_sg" {
  name   = "services-sg"
  vpc_id = aws_vpc.main.id

  # SSH from VPC (Debugging)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# C. DB SG
resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  # Allow Mongo from Services
  ingress {
    from_port       = var.mongodb_port
    to_port         = var.mongodb_port
    protocol        = "tcp"
    security_groups = [aws_security_group.services_sg.id]
  }

  # Allow SSH from VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- D. The Cycle Breakers (Separate Rules) ---

# Allow Services -> Master (K8s API)
resource "aws_security_group_rule" "master_ingress_k8s" {
  type                     = "ingress"
  from_port                = var.k8s_port
  to_port                  = var.k8s_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.services_sg.id
  security_group_id        = aws_security_group.master_sg.id
}

# Allow Master -> Services (Full Control)
resource "aws_security_group_rule" "services_ingress_master" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master_sg.id
  security_group_id        = aws_security_group.services_sg.id
}

# --- 5. Instances ---
resource "aws_instance" "master_node" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.master_instance_type
  subnet_id            = aws_subnet.public.id
  iam_instance_profile = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.master_sg.id]
  key_name             = "vockey"
  tags = { Name = "Master-Node" }
}

resource "aws_instance" "app_services" {
  count                = var.app_instance_count
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.app_instance_type
  subnet_id            = aws_subnet.private_app.id
  iam_instance_profile = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.services_sg.id]
  key_name             = "vockey"
  tags = { Name = "Service-${count.index + 1}" }
}

resource "aws_instance" "db_instance" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.db_instance_type
  subnet_id            = aws_subnet.private_db.id
  iam_instance_profile = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name             = "vockey"
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

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "Private-Route-Table" }
}

resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_db_assoc" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private_rt.id
}