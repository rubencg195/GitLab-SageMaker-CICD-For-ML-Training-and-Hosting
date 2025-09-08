# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.gitlab_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.gitlab_vpc.cidr_block
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

# GitLab Public Access Outputs
output "gitlab_public_ip" {
  description = "Public IP address of the GitLab server"
  value       = aws_eip.gitlab_eip.public_ip
}

output "gitlab_public_dns" {
  description = "Public DNS name of the GitLab server"
  value       = aws_instance.gitlab_server.public_dns
}

# GitLab Server Outputs
output "gitlab_instance_id" {
  description = "ID of the GitLab EC2 instance"
  value       = aws_instance.gitlab_server.id
}

output "gitlab_instance_private_ip" {
  description = "Private IP address of the GitLab server"
  value       = aws_instance.gitlab_server.private_ip
}

output "gitlab_elastic_ip" {
  description = "Elastic IP address of the GitLab server"
  value       = aws_eip.gitlab_eip.public_ip
}

# GitLab Access URLs (Public)
output "gitlab_http_url" {
  description = "HTTP URL to access GitLab"
  value       = "http://${aws_eip.gitlab_eip.public_ip}"
}

output "gitlab_https_url" {
  description = "HTTPS URL to access GitLab"
  value       = "https://${aws_eip.gitlab_eip.public_ip}"
}

output "gitlab_ssh_url" {
  description = "SSH URL for Git operations"
  value       = "git@${aws_eip.gitlab_eip.public_ip}:"
}


# Security Group Outputs
output "gitlab_security_group_id" {
  description = "ID of the GitLab security group"
  value       = aws_security_group.gitlab_sg.id
}

# EBS Volume Outputs
output "gitlab_data_volume_id" {
  description = "ID of the EBS volume for GitLab data"
  value       = aws_ebs_volume.gitlab_data.id
}

# Route53 Outputs (if using custom domain)
output "gitlab_domain_name" {
  description = "Custom domain name for GitLab"
  value       = aws_route53_record.gitlab_record.fqdn
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.gitlab_zone.zone_id
}

# CloudWatch Outputs
output "gitlab_log_group_name" {
  description = "CloudWatch log group name for GitLab"
  value       = aws_cloudwatch_log_group.gitlab_logs.name
}

# IAM Outputs
output "gitlab_iam_role_arn" {
  description = "ARN of the IAM role for GitLab instance"
  value       = aws_iam_role.gitlab_role.arn
}

output "gitlab_instance_profile_name" {
  description = "Name of the instance profile for GitLab"
  value       = aws_iam_instance_profile.gitlab_profile.name
}

# Connection Information
output "gitlab_ssh_connection_command" {
  description = "SSH command to connect to GitLab server"
  value       = "ssh -i ~/.ssh/id_rsa ${local.ssh_user}@${aws_eip.gitlab_eip.public_ip}"
}

# GitLab Credentials
output "gitlab_username" {
  description = "GitLab primary username for authentication"
  value       = local.gitlab_username
}

output "gitlab_password" {
  description = "GitLab primary password for authentication"
  value       = local.gitlab_password
  sensitive   = true
}

output "gitlab_root_username" {
  description = "GitLab root username"
  value       = "root"
}

output "gitlab_root_password" {
  description = "GitLab root password (retrieved from server)"
  value       = "Check /etc/gitlab/initial_root_password on server"
  sensitive   = true
}

# GitLab Setup Instructions
output "gitlab_setup_instructions" {
  description = "Instructions for GitLab access"
  value = <<-EOT
    GitLab has been deployed successfully!
    
    GITLAB ACCESS:
    - Public IP: ${aws_eip.gitlab_eip.public_ip}
    - Public DNS: ${aws_instance.gitlab_server.public_dns}
    - HTTP: http://${aws_eip.gitlab_eip.public_ip}
    - HTTPS: https://${aws_eip.gitlab_eip.public_ip}
    - SSH: ssh -i ~/.ssh/id_rsa ${local.ssh_user}@${aws_eip.gitlab_eip.public_ip}
    
    AUTHENTICATION REQUIRED:
    - Primary Username: ${local.gitlab_username}
    - Primary Password: ${local.gitlab_password}
    
    ROOT ACCESS (if needed):
    - Username: root
    - Password: Check /etc/gitlab/initial_root_password on the server
    
    SECURITY FEATURES:
    - Authentication is required for all access
    - User signup is disabled
    - Public projects are disabled by default
    - Session timeout: 8 hours
    - HTTPS redirect enabled
    - Security headers configured
    
    Note: GitLab may take 5-10 minutes to fully initialize after deployment.
  EOT
}
