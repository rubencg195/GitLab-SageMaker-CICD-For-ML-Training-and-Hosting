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

# Workspace Server Outputs
output "workspace_instance_id" {
  description = "ID of the Workspace EC2 instance"
  value       = aws_instance.workspace.id
}

output "workspace_public_ip" {
  description = "Public IP address of the Workspace server"
  value       = aws_instance.workspace.public_ip
}

output "workspace_public_dns" {
  description = "Public DNS name of the Workspace server"
  value       = aws_instance.workspace.public_dns
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
  value       = "WORKSPACE-${substr(aws_instance.workspace.id, -8, -1)}-${substr(aws_instance.workspace.public_ip, -4, -1)}"
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

# Workspace Access URLs
output "workspace_http_url" {
  description = "HTTP URL to access workspace"
  value       = "http://${aws_instance.workspace.public_ip}"
}

output "workspace_rdp_url" {
  description = "RDP URL to access workspace desktop"
  value       = "rdp://${aws_instance.workspace.public_ip}:${local.workspace_rdp_port}"
}

output "workspace_vnc_url" {
  description = "VNC URL to access workspace desktop"
  value       = "vnc://${aws_instance.workspace.public_ip}:${local.workspace_vnc_port}"
}

output "workspace_code_server_url" {
  description = "VS Code Server URL"
  value       = "http://${aws_instance.workspace.public_ip}:8080"
}

output "workspace_web_client_url" {
  description = "Amazon WorkSpaces Web Client URL"
  value       = "https://us-east-1.webclient.amazonworkspaces.com/registration"
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
output "workspace_ssh_connection_command" {
  description = "SSH command to connect to workspace server"
  value       = "ssh -i ~/.ssh/id_rsa ${local.ssh_user}@${aws_instance.workspace.public_ip}"
}

output "gitlab_ssh_connection_command" {
  description = "SSH command to connect to GitLab server via workspace"
  value       = "ssh -i ~/.ssh/id_rsa ${local.ssh_user}@${aws_instance.workspace.public_ip} 'ssh ${local.ssh_user}@${aws_instance.gitlab_server.private_ip}'"
}

# Workspace Setup Instructions
output "workspace_setup_instructions" {
  description = "Instructions for workspace and GitLab access"
  value = <<-EOT
    Workspace and GitLab have been deployed successfully!
    
    WORKSPACE ACCESS:
    - Public IP: ${aws_instance.workspace.public_ip}
    - Username: ${local.workspace_username}
    - Password: ${local.workspace_password}
    - Registration Code: WORKSPACE-${aws_workspace_workspace.workspace.id}
    
    Workspace Access Methods:
    1. Amazon WorkSpaces Web Client: https://us-east-1.webclient.amazonworkspaces.com/registration
    2. SSH: ssh -i ~/.ssh/id_rsa ${local.ssh_user}@${aws_instance.workspace.public_ip}
    3. RDP: rdp://${aws_instance.workspace.public_ip}:${local.workspace_rdp_port}
    4. VNC: vnc://${aws_instance.workspace.public_ip}:${local.workspace_vnc_port}
    5. VS Code Server: http://${aws_instance.workspace.public_ip}:8080
    
    GITLAB ACCESS (via Workspace):
    - Private IP: ${aws_instance.gitlab_server.private_ip}
    - HTTP: http://${aws_instance.gitlab_server.private_ip}
    - HTTPS: https://${aws_instance.gitlab_server.private_ip}
    
    To access GitLab:
    1. Connect to workspace using any method above
    2. From workspace, access GitLab at http://${aws_instance.gitlab_server.private_ip}
    3. To get GitLab root password, run from workspace:
       ssh ${local.ssh_user}@${aws_instance.gitlab_server.private_ip} "sudo cat /etc/gitlab/initial_root_password"
    
    Default GitLab username: root
    
    SECURITY:
    - GitLab is now in a private subnet and only accessible through the workspace
    - Workspace acts as a bastion host for secure access
    - All GitLab traffic is routed through the workspace security group
    
    Note: It may take a few minutes for both workspace and GitLab to fully initialize.
  EOT
}
