locals {
  # Project configuration
  project_name = "gitlab-server"
  environment  = "production"
  
  # AWS Configuration
  aws_region = "us-east-1"
  availability_zones = ["us-east-1a", "us-east-1b"]
  
  # VPC Configuration
  vpc_cidr = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
  
  # GitLab Configuration
  # Instance type: t3.large (recommended), t3.xlarge/c5.xlarge (faster setup), t3.medium (minimal)
  # For faster deployment, consider: t3.xlarge, c5.xlarge, m5.xlarge
  gitlab_instance_type = "t3.large"  
  gitlab_volume_size = 100
  gitlab_volume_type = "gp3"  # gp3 provides better performance than gp2
  ubuntu_ami_id = "ami-0bbdd8c17ed981ef9" # Ubuntu 22.04 LTS in us-east-1
  
  # Root Volume Configuration
  root_volume_size = 20
  root_volume_type = "gp3"
  
  # EBS Volume Configuration
  ebs_device_name = "/dev/sdf"
  
  # Security Groups
  gitlab_ssh_port = 22
  gitlab_http_port = 80
  gitlab_https_port = 443
  gitlab_ssh_port_alt = 2222
  
  # Network Configuration
  internet_cidr = "0.0.0.0/0"
  all_protocols = "-1"
  tcp_protocol = "tcp"
  
  # SSH Configuration
  ssh_key_path = "~/.ssh/id_rsa.pub"
  ssh_user = "ubuntu"
  
  # Route53 Configuration
  domain_name = "gitlab.local"
  subdomain_name = "gitlab"
  record_type = "A"
  ttl = 300
  
  # CloudWatch Configuration
  log_retention_days = 30
  
  # GitLab External URL (will be set dynamically)
  gitlab_external_url = "http://CHANGE_ME_AFTER_DEPLOYMENT"
  
  # GitLab Credentials
  gitlab_username = "gitlabuser"
  gitlab_password = "MyStr0ngP@ssw0rd!2024"
  
  # Workspace Configuration
  workspace_username = "ubuntu"
  workspace_password = "workspace123!"
  
  # Security Group Configuration
  workspace_ssh_port = 22
  workspace_rdp_port = 3389
  workspace_vnc_port = 5900
  
  # IAM Configuration
  iam_policy_version = "2012-10-17"
  ec2_service_principal = "ec2.amazonaws.com"
  
  # Tags
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = "devops-team"
  }
  
  # GitLab specific tags
  gitlab_tags = merge(local.common_tags, {
    Name        = "${local.project_name}-gitlab-server"
    Role        = "gitlab-server"
    Application = "gitlab"
  })
}
