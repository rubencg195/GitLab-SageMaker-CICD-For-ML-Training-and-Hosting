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

# Security Group for WorkSpaces Directory
resource "aws_security_group" "workspace_sg" {
  name_prefix = "${local.project_name}-workspace-"
  vpc_id      = aws_vpc.gitlab_vpc.id

  # WorkSpaces PCoIP access
  ingress {
    from_port   = 4172
    to_port     = 4172
    protocol    = "udp"
    cidr_blocks = [local.internet_cidr]
    description = "WorkSpaces PCoIP access"
  }

  # WorkSpaces PCoIP access (TCP)
  ingress {
    from_port   = 4172
    to_port     = 4172
    protocol    = local.tcp_protocol
    cidr_blocks = [local.internet_cidr]
    description = "WorkSpaces PCoIP access (TCP)"
  }

  # WorkSpaces WSP access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = local.tcp_protocol
    cidr_blocks = [local.internet_cidr]
    description = "WorkSpaces WSP access"
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

  # SSH access from WorkSpaces directory only
  ingress {
    from_port       = local.gitlab_ssh_port
    to_port         = local.gitlab_ssh_port
    protocol        = local.tcp_protocol
    cidr_blocks     = aws_subnet.private_subnets[*].cidr_block
    description     = "SSH access from WorkSpaces directory"
  }

  # HTTP access from WorkSpaces directory only
  ingress {
    from_port       = local.gitlab_http_port
    to_port         = local.gitlab_http_port
    protocol        = local.tcp_protocol
    cidr_blocks     = aws_subnet.private_subnets[*].cidr_block
    description     = "HTTP access from WorkSpaces directory"
  }

  # HTTPS access from WorkSpaces directory only
  ingress {
    from_port       = local.gitlab_https_port
    to_port         = local.gitlab_https_port
    protocol        = local.tcp_protocol
    cidr_blocks     = aws_subnet.private_subnets[*].cidr_block
    description     = "HTTPS access from WorkSpaces directory"
  }

  # GitLab SSH access (alternative port) from WorkSpaces directory only
  ingress {
    from_port       = local.gitlab_ssh_port_alt
    to_port         = local.gitlab_ssh_port_alt
    protocol        = local.tcp_protocol
    cidr_blocks     = aws_subnet.private_subnets[*].cidr_block
    description     = "GitLab SSH access from WorkSpaces directory"
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

# AWS WorkSpaces Directory
resource "aws_workspaces_directory" "workspace_directory" {
  directory_id = aws_directory_service_directory.workspace_ad.id
  subnet_ids   = aws_subnet.private_subnets[*].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-workspace-directory"
  })
}

# AWS Directory Service (Simple AD)
resource "aws_directory_service_directory" "workspace_ad" {
  name     = "workspace.${local.domain_name}"
  password = local.workspace_password
  size     = "Small"

  vpc_settings {
    vpc_id     = aws_vpc.gitlab_vpc.id
    subnet_ids = aws_subnet.private_subnets[*].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-workspace-ad"
  })
}

# AWS WorkSpace
resource "aws_workspaces_workspace" "workspace" {
  directory_id = aws_workspaces_directory.workspace_directory.id
  bundle_id    = data.aws_workspaces_bundle.workspace_bundle.id
  user_name    = local.workspace_username

  root_volume_encryption_enabled = true
  user_volume_encryption_enabled  = true
  volume_encryption_key           = aws_kms_key.workspace_key.arn

  workspace_properties {
    compute_type_name                         = "STANDARD"
    user_volume_size_gib                      = 50
    root_volume_size_gib                      = 80
    running_mode                              = "AUTO_STOP"
    running_mode_auto_stop_timeout_in_minutes = 60
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-workspace"
    Role = "workspace"
    Application = "workspace"
  })

  depends_on = [aws_workspaces_directory.workspace_directory]
}

# KMS Key for WorkSpace encryption
resource "aws_kms_key" "workspace_key" {
  description             = "KMS key for WorkSpace encryption"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-workspace-key"
  })
}

# KMS Key Alias
resource "aws_kms_alias" "workspace_key_alias" {
  name          = "alias/${local.project_name}-workspace-key"
  target_key_id = aws_kms_key.workspace_key.key_id
}

# Data source for WorkSpace bundle
data "aws_workspaces_bundle" "workspace_bundle" {
  bundle_id = "wsb-1jjj1k0kj" # Amazon Linux 2 (Standard) bundle
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

  user_data = base64encode(templatefile("${path.module}/scripts/gitlab-install.sh", {
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
