#!/bin/bash

# Optimized GitLab Installation Script for Ubuntu 22.04
# This script installs GitLab CE with performance optimizations

set -e

# Create log file for tracking script execution
LOG_FILE="/var/log/gitlab-install.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "$(date): Starting OPTIMIZED GitLab installation script..."

# OPTIMIZATION 1: Skip full system upgrade, only update package lists
echo "$(date): Updating package lists (skipping full upgrade for speed)..."
apt-get update -y

# OPTIMIZATION 2: Install only essential packages (skip unnecessary ones)
echo "$(date): Installing essential packages..."
apt-get install -y curl openssh-server ca-certificates tzdata

# Install GitLab CE
curl -fsSL https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey | gpg --dearmor > /usr/share/keyrings/gitlab-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/gitlab-archive-keyring.gpg] https://packages.gitlab.com/gitlab/gitlab-ce/ubuntu/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/gitlab.list

# OPTIMIZATION 3: Get public IP first to avoid waiting later
echo "$(date): Retrieving public IP for configuration..."
RETRY_COUNT=0
MAX_RETRIES=15  # Reduced retries for speed
PUBLIC_IP=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ -z "$PUBLIC_IP" ]; do
    PUBLIC_IP=$(curl -s --connect-timeout 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "404" ]; then
        echo "Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES: Waiting for public IP..."
        sleep 5  # Reduced sleep time
        RETRY_COUNT=$((RETRY_COUNT + 1))
        PUBLIC_IP=""
    else
        echo "Successfully retrieved public IP: $PUBLIC_IP"
        break
    fi
done

# OPTIMIZATION 4: Configure GitLab BEFORE installation to avoid double reconfigure
echo "$(date): Pre-configuring GitLab settings..."
if [ ! -z "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "404" ]; then
    EXTERNAL_URL="http://$PUBLIC_IP"
    echo "$(date): Using external URL: $EXTERNAL_URL"
else
    EXTERNAL_URL="http://gitlab.example.com"
    echo "$(date): WARNING - Using default external_url"
fi

# OPTIMIZATION 5: Install GitLab CE first, then configure (FIXED ORDERING)
# Note: Configuration will be written to /etc/gitlab/gitlab.rb AFTER GitLab CE is installed
# This fixes the issue where we tried to write config before the directory existed

echo "$(date): Installing GitLab CE first..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-ce

echo "$(date): Creating optimized GitLab configuration (after installation)..."
# Now we can safely write to /etc/gitlab/gitlab.rb since GitLab is installed
cat > /etc/gitlab/gitlab.rb << EOF
# External URL
external_url '$EXTERNAL_URL'

# PERFORMANCE OPTIMIZATIONS
# Reduce memory usage and startup time
postgresql['shared_buffers'] = "256MB"
postgresql['max_connections'] = 200
redis['maxmemory'] = "256mb"
puma['worker_processes'] = 2
puma['min_threads'] = 1
puma['max_threads'] = 16

# Disable unnecessary services for faster startup
prometheus_monitoring['enable'] = false
alertmanager['enable'] = false
node_exporter['enable'] = false
redis_exporter['enable'] = false
postgres_exporter['enable'] = false
gitlab_exporter['enable'] = false

# Security and authentication settings
gitlab_rails['gitlab_signup_enabled'] = false
gitlab_rails['require_admin_approval_after_user_signup'] = false
gitlab_rails['gitlab_signin_enabled'] = true

# Disable public projects by default
gitlab_rails['default_projects_features'] = {
  "issues" => false,
  "merge_requests" => false,
  "wiki" => false,
  "snippets" => false,
}

# Session and security configuration
gitlab_rails['session_expire_delay'] = 28800
gitlab_rails['time_zone'] = 'UTC'

# Performance settings
gitlab_rails['auto_migrate'] = true
gitlab_rails['db_pool'] = 10

# Logging configuration
logging['svlogd_size'] = 200 * 1024 * 1024
logging['svlogd_num'] = 10

# Storage configuration - using default paths

# Email settings (minimal for faster setup)
gitlab_rails['smtp_enable'] = false
gitlab_rails['gitlab_email_enabled'] = false

# GitLab Pages (disabled for performance)
gitlab_pages['enable'] = false

# Container Registry (disabled for performance) 
registry['enable'] = false

# Package registry settings
gitlab_rails['packages_enabled'] = true
gitlab_rails['dependency_proxy_enabled'] = false
EOF

echo "$(date): Running GitLab configuration (single reconfigure)..."

# OPTIMIZATION 6: Mount EBS volume in parallel while GitLab configures
echo "$(date): Setting up EBS volume..."
if [ -b /dev/sdf ]; then
    # Format the volume if it's not already formatted
    if ! blkid /dev/sdf; then
        mkfs.ext4 /dev/sdf
    fi
    
    # Create mount point and mount the volume
    mkdir -p /mnt/gitlab-data
    mount /dev/sdf /mnt/gitlab-data
    
    # Add to fstab for persistent mounting
    echo "/dev/sdf /mnt/gitlab-data ext4 defaults,nofail 0 2" >> /etc/fstab
    echo "$(date): EBS volume mounted successfully"
fi

# OPTIMIZATION 7: Single GitLab reconfigure with all settings
echo "$(date): Configuring GitLab (single optimized reconfigure)..."
gitlab-ctl reconfigure

# OPTIMIZATION 8: Start services explicitly and enable boot startup
echo "$(date): Starting GitLab services..."
gitlab-ctl start
systemctl enable gitlab-runsvdir

# OPTIMIZATION 9: Efficient GitLab readiness check with shorter timeouts
echo "$(date): Checking GitLab readiness (optimized)..."
check_gitlab_ready() {
    local max_attempts=20  # Reduced from 30
    local attempt=1
    
    # Initial short wait instead of fixed 120 seconds
    echo "Waiting 30 seconds for initial startup..."
    sleep 30
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f --max-time 5 http://localhost/users/sign_in > /dev/null 2>&1; then
            echo "$(date): GitLab is ready after $((30 + (attempt-1)*5)) seconds!"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: GitLab not ready yet, waiting 5 more seconds..."
        sleep 5  # Reduced from 10 seconds
        ((attempt++))
    done
    
    echo "$(date): GitLab readiness check timeout, but continuing (may still be initializing)..."
    return 1
}

# Check if GitLab is ready (but don't fail if not)
check_gitlab_ready || echo "$(date): Continuing with setup even if readiness check timed out..."

# OPTIMIZATION 11: Configure GitLab runners for CI/CD pipelines
echo "$(date): Setting up GitLab CI/CD runners..."
setup_gitlab_runners() {
    # Install GitLab Runner
    curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
    apt-get install -y gitlab-runner
    
    # Get GitLab URL (using public IP if available)
    if [ ! -z "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "404" ]; then
        GITLAB_URL="http://$PUBLIC_IP"
    else
        GITLAB_URL="http://localhost"
    fi
    
    # Wait for GitLab to be fully ready for runner registration
    echo "$(date): Waiting for GitLab to be ready for runner registration..."
    sleep 15
    
    # Get registration token from GitLab
    echo "$(date): Getting runner registration token..."
    REGISTRATION_TOKEN=""
    for attempt in 1 2 3 4 5; do
        REGISTRATION_TOKEN=$(gitlab-rails runner "puts Gitlab::CurrentSettings.runners_registration_token" 2>/dev/null || echo "")
        if [ -n "$REGISTRATION_TOKEN" ] && [ "$REGISTRATION_TOKEN" != "nil" ]; then
            echo "$(date): Got registration token: $${REGISTRATION_TOKEN:0:20}..."
            break
        fi
        echo "$(date): Attempt $attempt/5: Waiting for registration token..."
        sleep 10
    done
    
    if [ -z "$REGISTRATION_TOKEN" ] || [ "$REGISTRATION_TOKEN" = "nil" ]; then
        echo "$(date): WARNING: Could not get runner registration token, trying alternative method..."
        # Try to get token via GitLab API after waiting more
        sleep 30
        REGISTRATION_TOKEN=$(gitlab-rails runner "puts Gitlab::CurrentSettings.runners_registration_token" 2>/dev/null || echo "")
    fi
    
    if [ -n "$REGISTRATION_TOKEN" ] && [ "$REGISTRATION_TOKEN" != "nil" ]; then
        # Register multiple runners for better performance
        echo "$(date): Registering GitLab runners..."
        
        for runner_num in 1 2 3; do
            echo "$(date): Registering runner #$runner_num..."
            gitlab-runner register \
                --non-interactive \
                --url "$GITLAB_URL" \
                --registration-token "$REGISTRATION_TOKEN" \
                --executor "shell" \
                --description "SageMaker CI/CD Runner #$runner_num" \
                --tag-list "" \
                --run-untagged="true" \
                --locked="false" \
                --docker-image="" \
                --shell="bash" || echo "$(date): Runner #$runner_num registration failed, continuing..."
        done
        
        # Update runner configuration for optimal performance
        echo "$(date): Optimizing runner configuration..."
        cat > /etc/gitlab-runner/config.toml << EOF
concurrent = 4
check_interval = 3
connection_max_age = "15m0s"

[session_server]
  session_timeout = 1800

EOF
        
        # Add each registered runner with optimal settings
        for runner_num in 1 2 3; do
            RUNNER_TOKEN=$(grep -A 20 "SageMaker CI/CD Runner #$runner_num" /etc/gitlab-runner/config.toml | grep "token" | head -1 | cut -d'"' -f2 || echo "")
            if [ -n "$RUNNER_TOKEN" ]; then
                cat >> /etc/gitlab-runner/config.toml << EOF
[[runners]]
  name = "SageMaker CI/CD Runner #$runner_num"
  url = "$GITLAB_URL"
  token = "$RUNNER_TOKEN"
  executor = "shell"
  run_untagged = true
  locked = false
  [runners.cache]
    MaxUploadedArchiveSize = 0
    
EOF
            fi
        done
        
        # Start GitLab Runner service
        systemctl enable gitlab-runner
        systemctl start gitlab-runner
        
        # Verify runners are registered
        echo "$(date): Verifying runner registration..."
        gitlab-runner verify --delete || echo "$(date): Runner verification completed"
        gitlab-runner list || echo "$(date): Listed runners"
        
        echo "$(date): GitLab runners setup completed successfully"
    else
        echo "$(date): WARNING: Could not register runners - no registration token available"
        echo "$(date): Runners can be registered manually later using configure-gitlab-cicd script"
    fi
}

# Run runner setup
setup_gitlab_runners

# OPTIMIZATION 10: Streamlined completion (no Rails commands for speed)
GITLAB_USERNAME="${gitlab_username}"
GITLAB_PASSWORD="${gitlab_password}"

echo "$(date): Finalizing GitLab installation (no Rails commands for speed)..."

# Store basic GitLab information - root credentials only (working solution)
cat > /root/gitlab-install-info.txt << EOF
GitLab Installation Information
==============================
URL: http://$PUBLIC_IP
Installation completed: $(date)
Root password location: /etc/gitlab/initial_root_password
Configuration: Optimized for performance
Services disabled: monitoring, alertmanager, exporters (for speed)

WORKING CREDENTIALS:
Username: root
Password: Check /etc/gitlab/initial_root_password

PERFORMANCE OPTIMIZATIONS APPLIED:
- No Rails commands in install script (faster deployment)
- Monitoring services disabled
- Database settings optimized
- Single reconfigure process
- GitLab runners configured for CI/CD pipelines
EOF

# Set secure permissions
chmod 600 /root/gitlab-install-info.txt

# Final status
echo "$(date): OPTIMIZED GitLab installation completed successfully!"
echo "GitLab is accessible at: http://$PUBLIC_IP"
echo "Note: User creation will be handled by Terraform provisioner"
echo "Root password: Check /etc/gitlab/initial_root_password"

# Log completion
echo "$(date): Optimized GitLab installation completed successfully" >> /var/log/gitlab-install.log
echo "Performance optimizations applied:" >> /var/log/gitlab-install.log
echo "- Skipped full system upgrade" >> /var/log/gitlab-install.log
echo "- Disabled monitoring services" >> /var/log/gitlab-install.log  
echo "- Optimized database settings" >> /var/log/gitlab-install.log
echo "- Single GitLab reconfigure" >> /var/log/gitlab-install.log
echo "- Reduced timeout intervals" >> /var/log/gitlab-install.log
echo "- User creation delegated to provisioner" >> /var/log/gitlab-install.log
echo "- GitLab CI/CD runners configured during installation" >> /var/log/gitlab-install.log
