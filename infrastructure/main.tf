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

  # Allow all Inbound/Outbound (Using Variable)
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.anywhere_cidr  # <--- FIXED
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.anywhere_cidr  # <--- FIXED
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
    cidr_block = var.anywhere_cidr  # Trusting broadly for Lab ease
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.anywhere_cidr
    from_port  = 0
    to_port    = 0
  }
  tags = { Name = "App-NACL" }
}

resource "aws_network_acl" "db_acl" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_db.id]

  # Allow Inbound from VPC (Workers)
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
    cidr_block = var.anywhere_cidr  # <--- FIXED
    from_port  = 1024
    to_port    = 65535
  }

  # Outbound to Anywhere (For Updates via Master NAT)
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.anywhere_cidr  # <--- FIXED
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
    from_port   = var.http_port     # <--- FIXED
    to_port     = var.http_port     # <--- FIXED
    protocol    = "tcp"
    cidr_blocks = [var.web_access_cidr]
  }
  ingress {
    from_port   = var.jenkins_port  # <--- FIXED
    to_port     = var.jenkins_port  # <--- FIXED
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

  ingress {
    description = "K8s NodePorts"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.web_access_cidr]
  }

  # Outbound: Allow All
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.anywhere_cidr] # <--- FIXED
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
    cidr_blocks = [var.anywhere_cidr] # <--- FIXED
  }
}

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  # Allow MongoDB from VPC
  ingress {
    from_port   = var.mongodb_port  # <--- FIXED
    to_port     = var.mongodb_port  # <--- FIXED
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
    cidr_blocks = [var.anywhere_cidr] # <--- FIXED
  }
}
#tail -f /var/log/user-data.log
# --- 5. Instances ---
# MASTER NODE
resource "aws_instance" "master_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.public.id
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.master_sg.id]
  key_name               = "vockey"
  source_dest_check      = false

  user_data = <<-EOF
#!/bin/bash
# 1. LOGGING SETUP
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
export DEBIAN_FRONTEND=noninteractive

echo "--- [STEP 1] INSTALL TOOLS ---"
# Wait for apt lock
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done
apt-get update
apt-get install -y iptables-persistent openjdk-17-jre docker.io unzip wget

echo "--- [STEP 2] NETWORK CONFIGURATION ---"
# Enable IP Forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Enable Masquerading (Critical for Pod Internet Access)
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
netfilter-persistent save

echo "--- [STEP 3] INSTALL K3S ---"
curl -sfL https://get.k3s.io | K3S_TOKEN=mysecretpassword sh -

echo "--- [STEP 4] INSTALL JENKINS ---"
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update
apt-get install -y jenkins
systemctl stop jenkins

echo "--- [STEP 5] INSTALL KUBECTL (Required for your Jenkinsfile) ---"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo "--- [STEP 6] CONFIGURE KUBECONFIG FOR JENKINS ---"
# Your Jenkinsfile specifically asks for /var/lib/jenkins/.kube/config
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do sleep 2; done
mkdir -p /var/lib/jenkins/.kube
cp /etc/rancher/k3s/k3s.yaml /var/lib/jenkins/.kube/config
chown -R jenkins:jenkins /var/lib/jenkins/.kube
chmod 600 /var/lib/jenkins/.kube/config

echo "--- [STEP 7] INSTALL PLUGINS ---"
wget https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.12.13/jenkins-plugin-manager-2.12.13.jar
java -jar jenkins-plugin-manager-2.12.13.jar \
  --war /usr/share/java/jenkins.war \
  --plugin-download-directory /var/lib/jenkins/plugins \
  --plugins git workflow-aggregator docker-workflow

echo "--- [STEP 8] CONFIGURE JOB TO USE YOUR GIT REPO ---"
mkdir -p /var/lib/jenkins/jobs/My-Pipeline-App
cat <<XML > /var/lib/jenkins/jobs/My-Pipeline-App/config.xml
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Job using Jenkinsfile from Git</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/krd-ines/moleculer-realworld-example-app.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/aws-migration</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XML

echo "--- [STEP 9] CREATE CREDENTIALS ---"
mkdir -p /var/lib/jenkins/init.groovy.d

# 1. Admin User
cat <<GROOVY > /var/lib/jenkins/init.groovy.d/basic-security.groovy
import jenkins.model.*
import hudson.security.*
def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount('admin', 'admin123')
instance.setSecurityRealm(hudsonRealm)
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)
instance.save()
GROOVY

# 2. Docker Hub Credentials (docker-hub-creds)
cat <<GROOVY > /var/lib/jenkins/init.groovy.d/docker-creds.groovy
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import jenkins.model.Jenkins
def domain = Domain.global()
def store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()
def dockerCreds = new UsernamePasswordCredentialsImpl(
  CredentialsScope.GLOBAL,
  "docker-hub-creds",
  "Docker Hub Credentials",
  "mariaboukhelfa2025",
  "${var.dockerhub_password}"
)
if (store.getCredentials(domain).find { it.id == "docker-hub-creds" } == null) {
  store.addCredentials(domain, dockerCreds)
}
GROOVY

echo "--- [STEP 10] START JENKINS ---"
usermod -aG docker jenkins
chown -R jenkins:jenkins /var/lib/jenkins
chmod 666 /var/run/docker.sock

# Disable Setup Wizard
mkdir -p /etc/systemd/system/jenkins.service.d/
cat <<CONF > /etc/systemd/system/jenkins.service.d/override.conf
[Service]
Environment="JAVA_OPTS=-Djenkins.install.runSetupWizard=false"
CONF
systemctl daemon-reload

systemctl start jenkins
echo "Master Node Ready"
mkdir -p /home/ubuntu/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config
EOF

  tags = { Name = "Master-Node" }
}



# WORKER NODES
resource "aws_instance" "app_services" {
  count                  = var.app_instance_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private_app.id
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.services_sg.id]
  key_name               = "vockey"

  depends_on = [aws_instance.master_node]

  # --- CRITICAL: Using Variable for Port ---
  user_data = <<-EOF
              #!/bin/bash
              sleep 60
              # Using the k8s_port variable here:
              curl -sfL https://get.k3s.io | K3S_URL=https://${aws_instance.master_node.private_ip}:${var.k8s_port} K3S_TOKEN=mysecretpassword sh -
              EOF

  tags = { Name = "Service-Worker-${count.index + 1}" }
}

# DATABASE INSTANCE
resource "aws_instance" "db_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.private_db.id
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = "vockey"

  depends_on = [aws_instance.master_node]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y mongodb
              sed -i 's/bind_ip = 127.0.0.1/bind_ip = 0.0.0.0/' /etc/mongodb.conf
              systemctl restart mongodb
              EOF

  tags = { Name = "DB-Instance" }
}

# --- 6. Route Tables ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = var.anywhere_cidr # <--- FIXED
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
  tags = { Name = "Private-Route-Table" }
}


resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = var.anywhere_cidr
  network_interface_id   = aws_instance.master_node.primary_network_interface_id
}

resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_db_assoc" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private_rt.id
}