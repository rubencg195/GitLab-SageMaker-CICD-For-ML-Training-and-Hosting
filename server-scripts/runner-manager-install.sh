#!/bin/bash

# GitLab Runner Manager Installation Script
# Based on GitLab documentation for Docker Machine autoscaling on AWS
# Reference: https://docs.gitlab.com/runner/configuration/runner_autoscale_aws/

set -e

# Configuration from Terraform
GITLAB_SERVER_IP="${gitlab_server_ip}"
RUNNER_CACHE_BUCKET="${runner_cache_bucket}"
RUNNER_INSTANCE_PROFILE="${runner_instance_profile}"
RUNNER_SECURITY_GROUP="${runner_security_group}"
VPC_ID="${vpc_id}"
SUBNET_ID="${subnet_id}"
AWS_REGION="${aws_region}"

LOG_FILE="/var/log/gitlab-runner-manager-install.log"

# Create log file and redirect output
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "$(date): Starting GitLab Runner Manager installation..."
echo "GitLab Server IP: $GITLAB_SERVER_IP"
echo "Runner Cache Bucket: $RUNNER_CACHE_BUCKET"
echo "AWS Region: $AWS_REGION"

# Update system
echo "$(date): Updating system packages..."
apt-get update -y

# Install essential packages
echo "$(date): Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    awscli \
    unzip \
    python3 \
    python3-pip

# Install Docker
echo "$(date): Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

echo "$(date): Docker installation completed"

# Install GitLab Runner
echo "$(date): Installing GitLab Runner..."
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
apt-get install -y gitlab-runner

echo "$(date): GitLab Runner installation completed"

# Install Docker Machine (GitLab fork as per documentation)
echo "$(date): Installing Docker Machine (GitLab fork)..."
curl -L "https://gitlab-docker-machine-downloads.s3.amazonaws.com/main/docker-machine-Linux-x86_64" -o /usr/local/bin/docker-machine
chmod +x /usr/local/bin/docker-machine

# Verify Docker Machine installation
docker-machine version
echo "$(date): Docker Machine installation completed"

# Wait for GitLab server to be ready
echo "$(date): Waiting for GitLab server to be ready..."
wait_for_gitlab() {
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f --max-time 10 "http://$GITLAB_SERVER_IP/users/sign_in" > /dev/null 2>&1; then
            echo "$(date): GitLab server is ready!"
            return 0
        fi
        echo "$(date): Attempt $attempt/$max_attempts: GitLab server not ready, waiting 30 seconds..."
        sleep 30
        ((attempt++))
    done
    
    echo "$(date): WARNING: GitLab server may not be fully ready, but continuing..."
    return 1
}

wait_for_gitlab

# Get registration token from GitLab server
echo "$(date): Getting GitLab registration token..."
get_registration_token() {
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "$(date): Getting registration token (attempt $attempt/$max_attempts)..."
        
        local token=""
        token=$(timeout 30 ssh -i /home/ubuntu/.ssh/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$GITLAB_SERVER_IP "sudo gitlab-rails runner \"puts Gitlab::CurrentSettings.runners_registration_token\"" 2>/dev/null || echo "")
        
        if [ -n "$token" ] && [ "$token" != "nil" ] && [ $${#token} -gt 10 ]; then
            echo "$token"
            return 0
        fi
        
        echo "$(date): Token attempt $attempt failed, waiting..."
        sleep 15
        ((attempt++))
    done
    
    echo "$(date): ERROR: Could not get registration token"
    return 1
}

# Get AWS credentials for runner configuration
AWS_ACCESS_KEY_ID=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/) | jq -r .AccessKeyId)
AWS_SECRET_ACCESS_KEY=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/) | jq -r .SecretAccessKey)

echo "$(date): Registering GitLab Runner with docker+machine executor..."

# Register the GitLab Runner
REGISTRATION_TOKEN=$(get_registration_token)

if [ -z "$REGISTRATION_TOKEN" ]; then
    echo "$(date): ERROR: Cannot proceed without registration token"
    exit 1
fi

echo "$(date): Registering runner with token: $${REGISTRATION_TOKEN:0:20}..."

gitlab-runner register \
    --non-interactive \
    --url "http://$GITLAB_SERVER_IP" \
    --registration-token "$REGISTRATION_TOKEN" \
    --executor "docker+machine" \
    --description "GitLab AWS Autoscaler (SageMaker ML Training)" \
    --docker-image "ubuntu:20.04" \
    --docker-privileged="true" \
    --docker-disable-cache="true" \
    --limit=20

echo "$(date): GitLab Runner registered successfully!"

# Create the GitLab Runner configuration
echo "$(date): Creating GitLab Runner configuration..."
cat > /etc/gitlab-runner/config.toml << EOF
concurrent = 10
check_interval = 0
log_level = "info"
shutdown_timeout = 0

[session_server]
  session_timeout = 1800

[[runners]]
  name = "GitLab AWS Autoscaler (SageMaker ML Training)"
  url = "http://$GITLAB_SERVER_IP"
  executor = "docker+machine"
  limit = 20
  
  [runners.docker]
    image = "ubuntu:20.04"
    privileged = true
    disable_cache = true
    volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"]
    
  [runners.cache]
    Type = "s3"
    Shared = true
    [runners.cache.s3]
      ServerAddress = "s3.amazonaws.com"
      BucketName = "$RUNNER_CACHE_BUCKET"
      BucketLocation = "$AWS_REGION"
      Insecure = false
      
  [runners.machine]
    IdleCount = 1
    IdleTime = 1800
    MaxBuilds = 10
    MachineDriver = "amazonec2"
    MachineName = "gitlab-docker-machine-%s"
    MachineOptions = [
      "amazonec2-access-key=$AWS_ACCESS_KEY_ID",
      "amazonec2-secret-key=$AWS_SECRET_ACCESS_KEY",
      "amazonec2-region=$AWS_REGION",
      "amazonec2-vpc-id=$VPC_ID",
      "amazonec2-subnet-id=$SUBNET_ID",
      "amazonec2-use-private-address=true",
      "amazonec2-tags=gitlab-runner,true,gitlab-runner-autoscale,true,Environment,ml-training",
      "amazonec2-security-group=$RUNNER_SECURITY_GROUP",
      "amazonec2-instance-type=m5.large",
      "amazonec2-ami=ami-0c02fb55956c7d316",
      "amazonec2-iam-instance-profile=$RUNNER_INSTANCE_PROFILE",
      "amazonec2-ssh-user=ubuntu",
      "amazonec2-request-spot-instance=false",
      "amazonec2-root-size=20"
    ]
    
    # Autoscaling schedule for cost optimization
    [[runners.machine.autoscaling]]
      Periods = ["* * 9-17 * * mon-fri *"]
      IdleCount = 5
      IdleTime = 3600
      Timezone = "UTC"
    
    [[runners.machine.autoscaling]]  
      Periods = ["* * * * * sat,sun *"]
      IdleCount = 1
      IdleTime = 60
      Timezone = "UTC"
EOF

echo "$(date): GitLab Runner configuration created"

# Set proper ownership
chown gitlab-runner:gitlab-runner /etc/gitlab-runner/config.toml
chmod 600 /etc/gitlab-runner/config.toml

# Start GitLab Runner service
echo "$(date): Starting GitLab Runner service..."
systemctl restart gitlab-runner
systemctl enable gitlab-runner

# Wait a moment for service to start
sleep 10

# Verify runner status
echo "$(date): Verifying GitLab Runner status..."
gitlab-runner verify --delete || echo "$(date): Runner verification completed"
gitlab-runner list

# Check if runner is working
if gitlab-runner status | grep -q "alive"; then
    echo "$(date): ✅ GitLab Runner Manager is running successfully!"
else
    echo "$(date): ⚠️ GitLab Runner Manager may have issues"
fi

# Set up CloudWatch logging
echo "$(date): Setting up CloudWatch logging..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/gitlab-runner-manager-install.log",
            "log_group_name": "/aws/ec2/gitlab-runner",
            "log_stream_name": "{hostname}-manager-install",
            "retention_in_days": 7
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "GitLab/Runner",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Create health check script
cat > /usr/local/bin/runner-manager-health-check.sh << 'EOF'
#!/bin/bash
# Health check for GitLab Runner Manager

echo "=== GitLab Runner Manager Health Check ==="
echo "Date: $(date)"
echo ""

echo "Runner Status:"
gitlab-runner status

echo ""
echo "Runner List:"
gitlab-runner list

echo ""
echo "Docker Machine List:"
docker-machine ls 2>/dev/null || echo "No machines found"

echo ""
echo "System Resources:"
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
echo "Memory Usage: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
echo "Disk Usage: $(df -h / | awk 'NR==2{printf "%s", $5}')"

echo ""
echo "=== Health Check Complete ==="
EOF

chmod +x /usr/local/bin/runner-manager-health-check.sh

# Set up cron job for health checks
echo "*/15 * * * * /usr/local/bin/runner-manager-health-check.sh >> /var/log/runner-health.log 2>&1" | crontab -

# Final status report
echo "$(date): GitLab Runner Manager installation completed successfully!"
echo ""
echo "Configuration Summary:"
echo "  • GitLab Server: http://$GITLAB_SERVER_IP"
echo "  • Executor: docker+machine (with autoscaling)"
echo "  • Cache: S3 bucket $RUNNER_CACHE_BUCKET"
echo "  • Instance Profile: $RUNNER_INSTANCE_PROFILE"
echo "  • Security Group: $RUNNER_SECURITY_GROUP"
echo "  • Max concurrent builds: 20"
echo "  • Idle machines: 1 (can scale to 5 during business hours)"
echo "  • Machine type: m5.large (for ML workloads)"
echo "  • Health monitoring: Enabled with CloudWatch"
echo ""
echo "The runner manager will now automatically:"
echo "  • Spawn new Docker instances for CI/CD jobs"
echo "  • Scale based on workload and time schedules"
echo "  • Use SageMaker permissions for ML training"
echo "  • Cache build artifacts in S3"
echo ""
echo "Monitor the runner at: http://$GITLAB_SERVER_IP/admin/runners"
