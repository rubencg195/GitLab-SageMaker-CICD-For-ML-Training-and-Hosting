# CloudWatch Log Group for GitLab
resource "aws_cloudwatch_log_group" "gitlab_logs" {
  name              = "/aws/ec2/${local.project_name}-gitlab"
  retention_in_days = local.log_retention_days

  tags = local.common_tags
}
