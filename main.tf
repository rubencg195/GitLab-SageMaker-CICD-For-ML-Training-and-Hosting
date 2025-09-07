# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "gitlab_vpc" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "gitlab_igw" {
  vpc_id = aws_vpc.gitlab_vpc.id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count = length(local.public_subnet_cidrs)

  vpc_id                  = aws_vpc.gitlab_vpc.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-subnet-${count.index + 1}"
    Type = "public"
  })
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count = length(local.private_subnet_cidrs)

  vpc_id            = aws_vpc.gitlab_vpc.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-subnet-${count.index + 1}"
    Type = "private"
  })
}

# Route Table for Public Subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.gitlab_vpc.id

  route {
    cidr_block = local.internet_cidr
    gateway_id = aws_internet_gateway.gitlab_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-rt"
  })
}

# Route Table Association for Public Subnets
resource "aws_route_table_association" "public_rta" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-eip"
  })

  depends_on = [aws_internet_gateway.gitlab_igw]
}

# NAT Gateway
resource "aws_nat_gateway" "gitlab_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-gateway"
  })

  depends_on = [aws_internet_gateway.gitlab_igw]
}

# Route Table for Private Subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.gitlab_vpc.id

  route {
    cidr_block     = local.internet_cidr
    nat_gateway_id = aws_nat_gateway.gitlab_nat.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-rt"
  })
}

# Route Table Association for Private Subnets
resource "aws_route_table_association" "private_rta" {
  count = length(aws_subnet.private_subnets)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Security Group for Workspace (Bastion Host)
resource "aws_security_group" "workspace_sg" {
  name_prefix = "${local.project_name}-workspace-"
  vpc_id      = aws_vpc.gitlab_vpc.id

  # SSH access from internet
  ingress {
    from_port   = local.workspace_ssh_port
    to_port     = local.workspace_ssh_port
    protocol    = local.tcp_protocol
    cidr_blocks = [local.internet_cidr]
    description = "SSH access to workspace"
  }

  # RDP access from internet
  ingress {
    from_port   = local.workspace_rdp_port
    to_port     = local.workspace_rdp_port
    protocol    = local.tcp_protocol
    cidr_blocks = [local.internet_cidr]
    description = "RDP access to workspace"
  }

  # VNC access from internet
  ingress {
    from_port   = local.workspace_vnc_port
    to_port     = local.workspace_vnc_port
    protocol    = local.tcp_protocol
    cidr_blocks = [local.internet_cidr]
    description = "VNC access to workspace"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = local.all_protocols
    cidr_blocks = [local.internet_cidr]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-workspace-sg"
  })
}

# Security Group for GitLab Server (Private)
resource "aws_security_group" "gitlab_sg" {
  name_prefix = "${local.project_name}-gitlab-"
  vpc_id      = aws_vpc.gitlab_vpc.id

  # SSH access from workspace only
  ingress {
    from_port       = local.gitlab_ssh_port
    to_port         = local.gitlab_ssh_port
    protocol        = local.tcp_protocol
    security_groups = [aws_security_group.workspace_sg.id]
    description     = "SSH access from workspace"
  }

  # HTTP access from workspace only
  ingress {
    from_port       = local.gitlab_http_port
    to_port         = local.gitlab_http_port
    protocol        = local.tcp_protocol
    security_groups = [aws_security_group.workspace_sg.id]
    description     = "HTTP access from workspace"
  }

  # HTTPS access from workspace only
  ingress {
    from_port       = local.gitlab_https_port
    to_port         = local.gitlab_https_port
    protocol        = local.tcp_protocol
    security_groups = [aws_security_group.workspace_sg.id]
    description     = "HTTPS access from workspace"
  }

  # GitLab SSH access (alternative port) from workspace only
  ingress {
    from_port       = local.gitlab_ssh_port_alt
    to_port         = local.gitlab_ssh_port_alt
    protocol        = local.tcp_protocol
    security_groups = [aws_security_group.workspace_sg.id]
    description     = "GitLab SSH access from workspace"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = local.all_protocols
    cidr_blocks = [local.internet_cidr]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-gitlab-sg"
  })
}

# Key Pair for SSH access
resource "aws_key_pair" "gitlab_key" {
  key_name   = "${local.project_name}-key"
  public_key = file(local.ssh_key_path)

  tags = local.common_tags
}

# EBS Volume for GitLab data
resource "aws_ebs_volume" "gitlab_data" {
  availability_zone = aws_subnet.private_subnets[0].availability_zone
  size              = local.gitlab_volume_size
  type              = local.gitlab_volume_type
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-gitlab-data"
  })
}

# Workspace EC2 Instance (Bastion Host)
resource "aws_instance" "workspace" {
  ami                    = local.ubuntu_ami_id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.gitlab_key.key_name
  vpc_security_group_ids = [aws_security_group.workspace_sg.id]
  subnet_id              = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true

  root_block_device {
    volume_type = local.root_volume_type
    volume_size = local.root_volume_size
    encrypted   = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y ubuntu-desktop-minimal xrdp
    systemctl enable xrdp
    systemctl start xrdp
    
    # Create workspace user
    useradd -m -s /bin/bash ${local.workspace_username}
    echo "${local.workspace_username}:${local.workspace_password}" | chpasswd
    usermod -aG sudo ${local.workspace_username}
    usermod -aG adm ${local.workspace_username}
    
    # Configure auto-login
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-ubuntu.conf << 'EOL'
[SeatDefaults]
autologin-user=${local.workspace_username}
autologin-user-timeout=0
EOL
    
    # Install VS Code Server
    curl -fsSL https://code-server.dev/install.sh | sh
    systemctl enable --now code-server@${local.workspace_username}
    
    # Configure code-server
    mkdir -p /home/${local.workspace_username}/.config/code-server
    cat > /home/${local.workspace_username}/.config/code-server/config.yaml << 'EOL'
bind-addr: 0.0.0.0:8080
auth: password
password: ${local.workspace_password}
cert: false
EOL
    
    chown -R ${local.workspace_username}:${local.workspace_username} /home/${local.workspace_username}/.config
    
    # Install additional tools
    apt-get install -y git curl wget vim nano htop tree
    
    # Reboot to apply changes
    reboot
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-workspace"
    Role = "workspace"
    Application = "workspace"
  })

  depends_on = [aws_internet_gateway.gitlab_igw]
}

# GitLab EC2 Instance (Private)
resource "aws_instance" "gitlab_server" {
  ami                    = local.ubuntu_ami_id
  instance_type          = local.gitlab_instance_type
  key_name               = aws_key_pair.gitlab_key.key_name
  vpc_security_group_ids = [aws_security_group.gitlab_sg.id]
  subnet_id              = aws_subnet.private_subnets[0].id
  iam_instance_profile   = aws_iam_instance_profile.gitlab_profile.name
  associate_public_ip_address = false

  root_block_device {
    volume_type = local.root_volume_type
    volume_size = local.root_volume_size
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/gitlab-install.sh", {
    gitlab_external_url = local.gitlab_external_url
  }))

  tags = local.gitlab_tags

  depends_on = [aws_nat_gateway.gitlab_nat]
}

# Attach EBS volume to GitLab instance
resource "aws_volume_attachment" "gitlab_data_attachment" {
  device_name = local.ebs_device_name
  volume_id   = aws_ebs_volume.gitlab_data.id
  instance_id = aws_instance.gitlab_server.id
}

# Elastic IP for GitLab server
resource "aws_eip" "gitlab_eip" {
  instance = aws_instance.gitlab_server.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-gitlab-eip"
  })

  depends_on = [aws_internet_gateway.gitlab_igw]
}

# Route53 Hosted Zone (optional - for custom domain)
resource "aws_route53_zone" "gitlab_zone" {
  name = local.domain_name

  tags = local.common_tags
}

# Route53 Record for GitLab
resource "aws_route53_record" "gitlab_record" {
  zone_id = aws_route53_zone.gitlab_zone.zone_id
  name    = local.subdomain_name
  type    = local.record_type
  ttl     = local.ttl
  records = [aws_eip.gitlab_eip.public_ip]
}

# CloudWatch Log Group for GitLab
resource "aws_cloudwatch_log_group" "gitlab_logs" {
  name              = "/aws/ec2/${local.project_name}-gitlab"
  retention_in_days = local.log_retention_days

  tags = local.common_tags
}

# IAM Role for GitLab instance
resource "aws_iam_role" "gitlab_role" {
  name = "${local.project_name}-gitlab-role"

  assume_role_policy = jsonencode({
    Version = local.iam_policy_version
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = local.ec2_service_principal
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for GitLab
resource "aws_iam_policy" "gitlab_policy" {
  name = "${local.project_name}-gitlab-policy"

  policy = jsonencode({
    Version = local.iam_policy_version
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "gitlab_policy_attachment" {
  role       = aws_iam_role.gitlab_role.name
  policy_arn = aws_iam_policy.gitlab_policy.arn
}

# Instance Profile
resource "aws_iam_instance_profile" "gitlab_profile" {
  name = "${local.project_name}-gitlab-profile"
  role = aws_iam_role.gitlab_role.name

  tags = local.common_tags
}
