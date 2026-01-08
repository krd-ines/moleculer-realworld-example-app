# $Env:AWS_ACCESS_KEY_ID="ASIA..."
# $Env:AWS_SECRET_ACCESS_KEY="wJalrXU..."
# $Env:AWS_SESSION_TOKEN="FQoGZXI..."
# $Env:AWS_DEFAULT_REGION="us-east-1"
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
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.anywhere_cidr
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
  tags = { Name = "Public-NACL" }
}

resource "aws_network_acl" "app_acl" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_app.id]

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.anywhere_cidr
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
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = [var.web_access_cidr]
  }
  ingress {
    from_port   = var.jenkins_port
    to_port     = var.jenkins_port
    protocol    = "tcp"
    cidr_blocks = [var.web_access_cidr]
  }

  # Prometheus access
  ingress {
    description = "Prometheus"
    from_port   = 30090
    to_port     = 30090
    protocol    = "tcp"
    cidr_blocks = [var.web_access_cidr]
  }

  # Grafana access
  ingress {
    description = "Grafana"
    from_port   = 30030
    to_port     = 30030
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
    cidr_blocks = [var.anywhere_cidr]
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
    cidr_blocks = [var.anywhere_cidr]
  }
}

resource "aws_security_group" "db_sg" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  # Allow MongoDB from VPC
  ingress {
    from_port   = var.mongodb_port
    to_port     = var.mongodb_port
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
    cidr_blocks = [var.anywhere_cidr]
  }
}

# --- 5. Instances ---
# MASTER NODE
resource "aws_instance" "master_node" {
  # ... (Keep ami, instance_type, etc. exactly the same) ...
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.10"
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.master_sg.id]
  key_name               = "vockey"
  source_dest_check      = false

  user_data = <<-EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
export DEBIAN_FRONTEND=noninteractive

echo "--- [STEP 0] SETUP PERSISTENT EBS VOLUME (NITRO/T3 FIXED) ---"
MOUNT_POINT="/var/lib/jenkins"

# FIX: Simplified detection.
# We look for any NVMe disk starting with index 1 (e.g. nvme1n1), avoiding root (nvme0n1).
echo "Waiting for data volume..."
while true; do
  DEVICE_NAME=$(ls -1 /dev/nvme[1-9]n1 2>/dev/null | head -n 1)

  if [ ! -z "$DEVICE_NAME" ]; then
    echo "Found available volume: $DEVICE_NAME"
    break
  fi
  sleep 5
done

# Create filesystem if it doesn't exist
if ! blkid $DEVICE_NAME; then
  echo "Formatting new volume..."
  mkfs.ext4 $DEVICE_NAME
fi

# Create Mount Point and Mount
mkdir -p $MOUNT_POINT
mount $DEVICE_NAME $MOUNT_POINT

# Persistence
UUID=$(blkid -s UUID -o value $DEVICE_NAME)
echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
echo "Persistence ready at $MOUNT_POINT"

# ... (Keep STEP 1 through STEP 11 exactly the same as before) ...
echo "--- [STEP 1] INSTALL TOOLS ---"
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done
apt-get update
apt-get install -y iptables-persistent openjdk-17-jre docker.io unzip wget net-tools

echo "--- [STEP 2] NETWORK CONFIGURATION ---"
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

iptables -F
iptables -t nat -F
iptables -t nat -I POSTROUTING 1 -s 10.0.0.0/16 -o ens5 -j MASQUERADE
iptables -I FORWARD 1 -s 10.0.0.0/16 -j ACCEPT
iptables -I FORWARD 1 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 32448 -j ACCEPT

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

echo "--- [STEP 5] INSTALL KUBECTL ---"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo "--- [STEP 6] CONFIGURE KUBECONFIG FOR JENKINS ---"
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

echo "--- [STEP 8] CONFIGURE JOB ---"
mkdir -p /var/lib/jenkins/jobs/My-Pipeline-App
cat <<XML > /var/lib/jenkins/jobs/My-Pipeline-App/config.xml
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Job using Jenkinsfile from Git</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <quietPeriod>30</quietPeriod>
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
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XML

echo "--- [STEP 9] CREATE CREDENTIALS & TRIGGER ---"
mkdir -p /var/lib/jenkins/init.groovy.d

cat <<GROOVY > /var/lib/jenkins/init.groovy.d/limit-executors.groovy
import jenkins.model.*
Jenkins.instance.setNumExecutors(1)
Jenkins.instance.save()
GROOVY

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

cat <<GROOVY > /var/lib/jenkins/init.groovy.d/trigger-build.groovy
import jenkins.model.*
import hudson.model.*
Thread.sleep(10000)
def job = Jenkins.instance.getItem("My-Pipeline-App")
if (job != null) {
  job.scheduleBuild(new Cause.UserIdCause())
}
GROOVY

echo "--- [STEP 10] START JENKINS ---"
usermod -aG docker jenkins
chown -R jenkins:jenkins /var/lib/jenkins
chmod 666 /var/run/docker.sock
mkdir -p /etc/systemd/system/jenkins.service.d/
cat <<CONF > /etc/systemd/system/jenkins.service.d/override.conf
[Service]
Environment="JAVA_OPTS=-Djenkins.install.runSetupWizard=false"
CONF
systemctl daemon-reload
systemctl start jenkins

echo "--- [STEP 11] DOCKER DNS FIX & KUBECONFIG ---"
mkdir -p /etc/docker
echo '{"dns": ["8.8.8.8", "1.1.1.1"]}' > /etc/docker/daemon.json
systemctl restart docker

mkdir -p /home/ubuntu/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config
EOF

  tags = { Name = "Master-Node" }
}

# --- MASTER EBS VOLUME ---
resource "aws_ebs_volume" "master_vol" {
  availability_zone = aws_instance.master_node.availability_zone
  size              = 10
  tags              = { Name = "Master-Data-Volume" }
}

resource "aws_volume_attachment" "master_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.master_vol.id
  instance_id = aws_instance.master_node.id
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

  user_data = <<-EOF
    #!/bin/bash
    exec > /var/log/user-data.log 2>&1

    echo "--- [STEP 0] SETUP PERSISTENT EBS VOLUME (NITRO/T3 FIXED) ---"
    MOUNT_POINT="/var/lib/rancher"

    # FIX: Simple detection for NVMe drives (skipping root nvme0n1)
    echo "Waiting for data volume..."
    while true; do
      DEVICE_NAME=$(ls -1 /dev/nvme[1-9]n1 2>/dev/null | head -n 1)
      if [ ! -z "$DEVICE_NAME" ]; then
        echo "Found available volume: $DEVICE_NAME"
        break
      fi
      sleep 5
    done

    # Format if needed
    if ! blkid $DEVICE_NAME; then
      mkfs.ext4 $DEVICE_NAME
    fi

    mkdir -p $MOUNT_POINT
    mount $DEVICE_NAME $MOUNT_POINT

    # FIX: Use UUID for reliable mounting on reboot
    UUID=$(blkid -s UUID -o value $DEVICE_NAME)
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab

    echo "--- [STEP 1] NETWORK ---"
    echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
    until ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 5; done

    echo "--- [STEP 2] K3S WORKER ---"
    curl -sfL https://get.k3s.io | K3S_URL=https://10.0.1.10:${var.k8s_port} K3S_TOKEN=mysecretpassword sh -
  EOF

  tags = { Name = "Service-Worker-${count.index + 1}" }
}

# --- WORKER EBS VOLUMES ---
resource "aws_ebs_volume" "worker_vol" {
  count             = var.app_instance_count
  availability_zone = aws_instance.app_services[count.index].availability_zone
  size              = 10
  tags              = { Name = "Worker-Data-${count.index + 1}" }
}

resource "aws_volume_attachment" "worker_att" {
  count       = var.app_instance_count
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.worker_vol[count.index].id
  instance_id = aws_instance.app_services[count.index].id
}

#ssh -i "vockey.pem" ubuntu@10.0.3.100
#cat /var/log/user-data.log
# DATABASE INSTANCE
resource "aws_instance" "db_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.private_db.id
  private_ip             = "10.0.3.100"
  iam_instance_profile   = data.aws_iam_instance_profile.lab_profile.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = "vockey"
  depends_on             = [aws_instance.master_node]

  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

    echo "--- [STEP 0] SETUP PERSISTENT EBS VOLUME (NITRO/T3 FIXED) ---"
    MOUNT_POINT="/var/lib/mongodb"

    # FIX: Simple detection for NVMe drives
    echo "Waiting for data volume..."
    while true; do
      DEVICE_NAME=$(ls -1 /dev/nvme[1-9]n1 2>/dev/null | head -n 1)
      if [ ! -z "$DEVICE_NAME" ]; then
        echo "Found available volume: $DEVICE_NAME"
        break
      fi
      sleep 5
    done

    if ! blkid $DEVICE_NAME; then
      mkfs.ext4 $DEVICE_NAME
    fi

    mkdir -p $MOUNT_POINT
    mount $DEVICE_NAME $MOUNT_POINT

    # FIX: UUID for fstab
    UUID=$(blkid -s UUID -o value $DEVICE_NAME)
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab

    echo "--- [STEP 1] INSTALL MONGO ---"
    echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
    until ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 5; done

    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done
    apt-get update
    apt-get install -y mongodb

    chown -R mongodb:mongodb /var/lib/mongodb

    echo "--- [STEP 2] CONFIG ---"
    if [ -f /etc/mongodb.conf ]; then
        sed -i 's/bind_ip = 127.0.0.1/bind_ip = 0.0.0.0/g' /etc/mongodb.conf
    fi
    systemctl restart mongodb
    systemctl enable mongodb
  EOF

  tags = { Name = "DB-Instance" }
}

# --- DATABASE EBS VOLUME ---
resource "aws_ebs_volume" "db_vol" {
  availability_zone = aws_instance.db_instance.availability_zone
  size              = 10
  tags              = { Name = "DB-Data-Volume" }
}

resource "aws_volume_attachment" "db_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.db_vol.id
  instance_id = aws_instance.db_instance.id
}


# --- 6. Route Tables ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = var.anywhere_cidr
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