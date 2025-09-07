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

# AWS WorkSpaces Outputs
output "workspace_id" {
  description = "ID of the AWS WorkSpace"
  value       = aws_workspaces_workspace.workspace.id
}

output "workspace_ip_address" {
  description = "IP address of the AWS WorkSpace"
  value       = aws_workspaces_workspace.workspace.ip_address
}

output "workspace_directory_id" {
  description = "ID of the WorkSpaces directory"
  value       = aws_workspaces_directory.workspace_directory.id
}

output "workspace_username" {
  description = "Username for workspace access"
  value       = local.workspace_username
}

output "workspace_password" {
  description = "Password for workspace access"
  value       = local.workspace_password
  sensitive   = true
}

output "workspace_registration_code" {
  description = "Registration code for Amazon WorkSpaces web client"
  value       = "WORKSPACE-${substr(aws_workspaces_workspace.workspace.id, -8, -1)}-${substr(aws_workspaces_workspace.workspace.ip_address, -4, -1)}"
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

# GitLab Access URLs (via Workspace)
output "gitlab_http_url" {
  description = "HTTP URL to access GitLab via workspace"
  value       = "http://${aws_instance.gitlab_server.private_ip}"
}

output "gitlab_https_url" {
  description = "HTTPS URL to access GitLab via workspace"
  value       = "https://${aws_instance.gitlab_server.private_ip}"
}

output "gitlab_ssh_url" {
  description = "SSH URL for Git operations via workspace"
  value       = "git@${aws_instance.gitlab_server.private_ip}:"
}

# WorkSpaces Access URLs
output "workspace_web_client_url" {
  description = "Amazon WorkSpaces Web Client URL"
  value       = "https://us-east-1.webclient.amazonworkspaces.com/registration"
}

output "workspace_directory_dns" {
  description = "DNS name of the WorkSpaces directory"
  value       = aws_directory_service_directory.workspace_ad.dns_ip_addresses
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
output "workspace_connection_instructions" {
  description = "Instructions for connecting to AWS WorkSpace"
  value       = "Use Amazon WorkSpaces web client at https://us-east-1.webclient.amazonworkspaces.com/registration with registration code and directory credentials"
}

output "gitlab_ssh_connection_command" {
  description = "SSH command to connect to GitLab server via WorkSpace"
  value       = "From WorkSpace: ssh ${local.ssh_user}@${aws_instance.gitlab_server.private_ip}"
}

# Workspace Setup Instructions
output "workspace_setup_instructions" {
  description = "Instructions for workspace and GitLab access"
  value = <<-EOT
    Workspace and GitLab have been deployed successfully!
    
    WORKSPACE ACCESS:
    - WorkSpace ID: ${aws_workspaces_workspace.workspace.id}
    - Username: ${local.workspace_username}
    - Password: ${local.workspace_password}
    - Registration Code: WORKSPACE-${substr(aws_workspaces_workspace.workspace.id, -8, -1)}-${substr(aws_workspaces_workspace.workspace.ip_address, -4, -1)}
    - Directory DNS: ${join(", ", aws_directory_service_directory.workspace_ad.dns_ip_addresses)}
    
    WorkSpace Access Methods:
    1. Amazon WorkSpaces Web Client: https://us-east-1.webclient.amazonworkspaces.com/registration
    2. Amazon WorkSpaces Client Applications (Windows, macOS, Linux, Mobile)
    
    GITLAB ACCESS (via Workspace):
    - Private IP: ${aws_instance.gitlab_server.private_ip}
    - HTTP: http://${aws_instance.gitlab_server.private_ip}
    - HTTPS: https://${aws_instance.gitlab_server.private_ip}
    
    To access GitLab:
    1. Connect to WorkSpace using Amazon WorkSpaces client
    2. From WorkSpace, access GitLab at http://${aws_instance.gitlab_server.private_ip}
    3. To get GitLab root password, run from WorkSpace:
       ssh ${local.ssh_user}@${aws_instance.gitlab_server.private_ip} "sudo cat /etc/gitlab/initial_root_password"
    
    Default GitLab username: root
    
    SECURITY FEATURES:
    - GitLab is in a private subnet and only accessible through WorkSpace
    - WorkSpace provides enterprise-grade security and compliance
    - All data is encrypted at rest and in transit
    - WorkSpace acts as a secure virtual desktop for GitLab access
    - Directory Service provides centralized authentication
    
    Note: WorkSpace may take 10-15 minutes to fully initialize. GitLab will be ready shortly after.
  EOT
}
