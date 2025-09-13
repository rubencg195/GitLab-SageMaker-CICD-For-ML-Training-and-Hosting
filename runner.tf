# GitLab Runner Manager Configuration
# Based on GitLab documentation for Docker Machine autoscaling on AWS
# Reference: https://docs.gitlab.com/runner/configuration/runner_autoscale_aws/

# Using the same AMI as the GitLab server (defined in locals.tf)

# IAM Role for GitLab Runner Manager with full EC2 and SageMaker permissions
resource "aws_iam_role" "gitlab_runner_manager_role" {
  name = "gitlab-runner-manager-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "GitLab Runner Manager Role"
    Environment = "ml-training"
    Purpose     = "gitlab-runner-manager"
  }
}

# IAM Role for spawned runner instances (passed by Docker Machine)
resource "aws_iam_role" "gitlab_runner_instance_role" {
  name = "gitlab-runner-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "GitLab Runner Instance Role"
    Environment = "ml-training"
    Purpose     = "gitlab-runner-instance"
  }
}

# Policies for Runner Manager (needs to create/manage EC2 instances)
resource "aws_iam_role_policy_attachment" "manager_ec2_full_access" {
  role       = aws_iam_role.gitlab_runner_manager_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "manager_s3_full_access" {
  role       = aws_iam_role.gitlab_runner_manager_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "manager_ssm_access" {
  role       = aws_iam_role.gitlab_runner_manager_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Policies for spawned runner instances (SageMaker access)
resource "aws_iam_role_policy_attachment" "instance_sagemaker_access" {
  role       = aws_iam_role.gitlab_runner_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy_attachment" "instance_s3_access" {
  role       = aws_iam_role.gitlab_runner_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "instance_cloudwatch_access" {
  role       = aws_iam_role.gitlab_runner_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom policy for Runner Manager (needs to pass roles to created instances)
resource "aws_iam_role_policy" "manager_pass_role_policy" {
  name = "gitlab-runner-manager-pass-role"
  role = aws_iam_role.gitlab_runner_manager_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:ListInstanceProfiles",
          "iam:GetInstanceProfile"
        ]
        Resource = [
          aws_iam_role.gitlab_runner_instance_role.arn,
          "arn:aws:iam::*:instance-profile/gitlab-runner-instance-profile"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profiles
resource "aws_iam_instance_profile" "gitlab_runner_manager_profile" {
  name = "gitlab-runner-manager-profile"
  role = aws_iam_role.gitlab_runner_manager_role.name
}

resource "aws_iam_instance_profile" "gitlab_runner_instance_profile" {
  name = "gitlab-runner-instance-profile"
  role = aws_iam_role.gitlab_runner_instance_role.name
}

# Security group for GitLab Runner Manager
resource "aws_security_group" "gitlab_runner_manager_sg" {
  name_prefix = "gitlab-runner-manager-"
  vpc_id      = aws_vpc.gitlab_vpc.id
  description = "Security group for GitLab Runner Manager instance"

  # Outbound internet access (for package installation, Docker, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  # Allow all outbound traffic to VPC
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.gitlab_vpc.cidr_block]
    description = "All outbound traffic to VPC"
  }

  # SSH access for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access for management"
  }

  # Allow all inbound traffic from VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.gitlab_vpc.cidr_block]
    description = "Allow all inbound traffic from VPC"
  }

  tags = {
    Name = "GitLab Runner Manager Security Group"
  }
}

# Security group for Docker Machine spawned instances
resource "aws_security_group" "gitlab_runner_machines_sg" {
  name_prefix = "gitlab-runner-machines-"
  vpc_id      = aws_vpc.gitlab_vpc.id
  description = "Security group for Docker Machine spawned runner instances"

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.gitlab_sg.id]
    description     = "Allow all outbound traffic to GitLab server"
  }

  # SSH access from runner manager (Docker Machine requirement)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.gitlab_runner_manager_sg.id]
    description     = "SSH from runner manager"
  }

  # Docker daemon port (Docker Machine requirement)
  ingress {
    from_port       = 2376
    to_port         = 2376
    protocol        = "tcp"
    security_groups = [aws_security_group.gitlab_runner_manager_sg.id]
    description     = "Docker daemon from runner manager"
  }

  tags = {
    Name = "GitLab Runner Machines Security Group"
  }
}

# S3 bucket for GitLab Runner cache (as recommended by GitLab docs)
resource "aws_s3_bucket" "gitlab_runner_cache" {
  bucket_prefix = "gitlab-runner-cache-"
  force_destroy = true

  tags = {
    Name        = "GitLab Runner Cache"
    Purpose     = "gitlab-runner-cache"
    Environment = "ml-training"
  }
}

resource "aws_s3_bucket_versioning" "gitlab_runner_cache" {
  bucket = aws_s3_bucket.gitlab_runner_cache.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_runner_cache" {
  bucket = aws_s3_bucket.gitlab_runner_cache.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# GitLab Runner Manager Instance (single dedicated instance)
resource "aws_instance" "gitlab_runner_manager" {
  ami                    = local.ubuntu_ami_id
  instance_type          = "t3.medium"  # Small instance for manager only
  key_name               = aws_key_pair.gitlab_key.key_name
  subnet_id              = aws_subnet.public_subnets[0].id  # Public subnet for internet access
  vpc_security_group_ids = [aws_security_group.gitlab_runner_manager_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.gitlab_runner_manager_profile.name

  user_data = base64encode(templatefile("${path.module}/server-scripts/runner-manager-install.sh", {
    gitlab_server_ip              = aws_instance.gitlab_server.public_ip
    runner_cache_bucket          = aws_s3_bucket.gitlab_runner_cache.id
    runner_instance_profile      = aws_iam_instance_profile.gitlab_runner_instance_profile.name
    runner_security_group        = aws_security_group.gitlab_runner_machines_sg.id
    vpc_id                       = aws_vpc.gitlab_vpc.id
    subnet_id                    = aws_subnet.private_subnets[0].id
    aws_region                   = local.aws_region
    script_dir                   = "/opt/gitlab-scripts" # Set script_dir to the remote path where scripts will be copied
  }))

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name        = "GitLab Runner Manager"
    Purpose     = "gitlab-runner-manager"
    Environment = "ml-training"
  }
}

# CloudWatch Log Group for Runner logs
resource "aws_cloudwatch_log_group" "gitlab_runner_logs" {
  name              = "/aws/ec2/gitlab-runner"
  retention_in_days = 7

  tags = {
    Name        = "GitLab Runner Logs"
    Environment = "ml-training"
  }
}

# Outputs for GitLab Runner Manager
output "gitlab_runner_manager_instance_id" {
  description = "Instance ID of the GitLab Runner Manager"
  value       = aws_instance.gitlab_runner_manager.id
}

output "gitlab_runner_manager_ip" {
  description = "Public IP of the GitLab Runner Manager"
  value       = aws_instance.gitlab_runner_manager.public_ip
}

output "gitlab_runner_cache_bucket" {
  description = "S3 bucket for GitLab Runner cache"
  value       = aws_s3_bucket.gitlab_runner_cache.id
}

output "gitlab_runner_manager_security_group_id" {
  description = "Security Group ID for GitLab Runner Manager"
  value       = aws_security_group.gitlab_runner_manager_sg.id
}

output "gitlab_runner_machines_security_group_id" {
  description = "Security Group ID for Docker Machine spawned instances"
  value       = aws_security_group.gitlab_runner_machines_sg.id
}
