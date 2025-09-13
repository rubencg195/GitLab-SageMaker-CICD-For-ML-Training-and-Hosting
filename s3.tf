# S3 Bucket for GitLab CI/CD Artifacts
# This bucket stores zipped content from GitLab CI/CD pipelines

# S3 Bucket for storing CI/CD artifacts
resource "aws_s3_bucket" "gitlab_artifacts" {
  bucket = "rubenchevez-demo-gitlab-artifacts"
  force_destroy = true # Enable force destroy to clean up bucket contents on destroy

  tags = {
    Application = "gitlab-cicd"
    Project     = "gitlab-server"
    Role        = "gitlab-artifacts-storage"
    Environment = "production"
    ManagedBy   = "terraform"
    Owner       = "devops-team"
    Name        = "gitlab-server-artifacts-bucket"
    Purpose     = "ci-cd-artifacts"
  }
}

# Random suffix for unique bucket name

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  rule {
    id     = "artifact_retention"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Transition to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete after 1 year
    expiration {
      days = 365
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 Bucket Notification Configuration (for future Lambda triggers)
resource "aws_s3_bucket_notification" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  # Future: Add Lambda function notifications for artifact processing
  # lambda_function {
  #   lambda_function_arn = aws_lambda_function.artifact_processor.arn
  #   events              = ["s3:ObjectCreated:*"]
  #   filter_prefix       = "releases/"
  #   filter_suffix       = ".zip"
  # }
}

# S3 Bucket Policy for GitLab CI/CD Access
resource "aws_s3_bucket_policy" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitLabCICDAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.gitlab_ci_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.gitlab_artifacts.arn,
          "${aws_s3_bucket.gitlab_artifacts.arn}/*"
        ]
      },
      {
        Sid    = "GitLabServerAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.gitlab_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.gitlab_artifacts.arn,
          "${aws_s3_bucket.gitlab_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# S3 Bucket CORS Configuration (if needed for web access)
resource "aws_s3_bucket_cors_configuration" "gitlab_artifacts" {
  bucket = aws_s3_bucket.gitlab_artifacts.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# S3 Bucket for storing release notes and metadata
resource "aws_s3_bucket" "gitlab_releases" {
  bucket = "rubenchevez-demo-gitlab-releases"
  force_destroy = true # Enable force destroy to clean up bucket contents on destroy

  tags = {
    Application = "gitlab-cicd"
    Project     = "gitlab-server"
    Role        = "gitlab-releases-storage"
    Environment = "production"
    ManagedBy   = "terraform"
    Owner       = "devops-team"
    Name        = "gitlab-server-releases-bucket"
    Purpose     = "ci-cd-releases"
  }
}

# Random suffix for release bucket name

# S3 Bucket Versioning for releases
resource "aws_s3_bucket_versioning" "gitlab_releases" {
  bucket = aws_s3_bucket.gitlab_releases.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server Side Encryption for releases
resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_releases" {
  bucket = aws_s3_bucket.gitlab_releases.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block for releases
resource "aws_s3_bucket_public_access_block" "gitlab_releases" {
  bucket = aws_s3_bucket.gitlab_releases.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy for releases
resource "aws_s3_bucket_policy" "gitlab_releases" {
  bucket = aws_s3_bucket.gitlab_releases.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitLabCICDReleaseAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.gitlab_ci_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.gitlab_releases.arn,
          "${aws_s3_bucket.gitlab_releases.arn}/*"
        ]
      },
      {
        Sid    = "GitLabServerReleaseAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.gitlab_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.gitlab_releases.arn,
          "${aws_s3_bucket.gitlab_releases.arn}/*"
        ]
      }
    ]
  })
}
