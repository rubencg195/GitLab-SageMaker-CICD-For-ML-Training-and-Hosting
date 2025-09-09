# Security Group for GitLab Server (Public)
resource "aws_security_group" "gitlab_sg" {
  name_prefix = "${local.project_name}-gitlab-"
  vpc_id      = aws_vpc.gitlab_vpc.id

  # SSH access from anywhere
  ingress {
    from_port       = local.gitlab_ssh_port
    to_port         = local.gitlab_ssh_port
    protocol        = local.tcp_protocol
    cidr_blocks     = [local.internet_cidr]
    description     = "SSH access from anywhere"
  }

  # HTTP access from anywhere
  ingress {
    from_port       = local.gitlab_http_port
    to_port         = local.gitlab_http_port
    protocol        = local.tcp_protocol
    cidr_blocks     = [local.internet_cidr]
    description     = "HTTP access from anywhere"
  }

  # HTTPS access from anywhere
  ingress {
    from_port       = local.gitlab_https_port
    to_port         = local.gitlab_https_port
    protocol        = local.tcp_protocol
    cidr_blocks     = [local.internet_cidr]
    description     = "HTTPS access from anywhere"
  }

  # GitLab SSH access (alternative port) from anywhere
  ingress {
    from_port       = local.gitlab_ssh_port_alt
    to_port         = local.gitlab_ssh_port_alt
    protocol        = local.tcp_protocol
    cidr_blocks     = [local.internet_cidr]
    description     = "GitLab SSH access from anywhere"
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
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "arn:aws:s3:::${local.project_name}-${local.environment}-artifacts-*",
          "arn:aws:s3:::${local.project_name}-${local.environment}-artifacts-*/*",
          "arn:aws:s3:::${local.project_name}-${local.environment}-releases-*",
          "arn:aws:s3:::${local.project_name}-${local.environment}-releases-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
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

# IAM Role for GitLab CI/CD
resource "aws_iam_role" "gitlab_ci_role" {
  name = "${local.project_name}-gitlab-ci-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-gitlab-ci-role"
    Role = "gitlab-ci"
  })
}

# IAM Policy for GitLab CI/CD S3 Access
resource "aws_iam_policy" "gitlab_ci_s3_policy" {
  name = "${local.project_name}-gitlab-ci-s3-policy"

  policy = jsonencode({
    Version = local.iam_policy_version
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "arn:aws:s3:::${local.project_name}-${local.environment}-artifacts-*",
          "arn:aws:s3:::${local.project_name}-${local.environment}-artifacts-*/*",
          "arn:aws:s3:::${local.project_name}-${local.environment}-releases-*",
          "arn:aws:s3:::${local.project_name}-${local.environment}-releases-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach S3 policy to CI role
resource "aws_iam_role_policy_attachment" "gitlab_ci_s3_policy_attachment" {
  role       = aws_iam_role.gitlab_ci_role.name
  policy_arn = aws_iam_policy.gitlab_ci_s3_policy.arn
}

# IAM Policy for GitLab CI/CD CloudWatch Access
resource "aws_iam_policy" "gitlab_ci_cloudwatch_policy" {
  name = "${local.project_name}-gitlab-ci-cloudwatch-policy"

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
      }
    ]
  })

  tags = local.common_tags
}

# Attach CloudWatch policy to CI role
resource "aws_iam_role_policy_attachment" "gitlab_ci_cloudwatch_policy_attachment" {
  role       = aws_iam_role.gitlab_ci_role.name
  policy_arn = aws_iam_policy.gitlab_ci_cloudwatch_policy.arn
}

# Instance Profile for GitLab CI
resource "aws_iam_instance_profile" "gitlab_ci_profile" {
  name = "${local.project_name}-gitlab-ci-profile"
  role = aws_iam_role.gitlab_ci_role.name

  tags = local.common_tags
}