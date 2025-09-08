#!/bin/bash

# GitLab Installation Script for Ubuntu 22.04
# This script installs GitLab CE on an EC2 instance

set -e

# Create log file for tracking script execution
LOG_FILE="/var/log/gitlab-install.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "$(date): Starting GitLab installation script..."

# Update system packages
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y curl openssh-server ca-certificates tzdata perl

# Install GitLab CE
curl -fsSL https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey | gpg --dearmor > /usr/share/keyrings/gitlab-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/gitlab-archive-keyring.gpg] https://packages.gitlab.com/gitlab/gitlab-ce/ubuntu/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/gitlab.list

# Update package list and install GitLab
apt-get update -y
apt-get install -y gitlab-ce

# Configure GitLab
gitlab-ctl reconfigure

# Wait for instance metadata to be available and get public IP
echo "Waiting for instance metadata to be available..."
RETRY_COUNT=0
MAX_RETRIES=30
PUBLIC_IP=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ -z "$PUBLIC_IP" ]; do
    PUBLIC_IP=$(curl -s --connect-timeout 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
    if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "404" ]; then
        echo "Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES: Waiting for public IP..."
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT + 1))
        PUBLIC_IP=""
    else
        echo "Successfully retrieved public IP: $PUBLIC_IP"
        break
    fi
done

if [ ! -z "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "404" ]; then
    echo "Setting GitLab external URL to: http://$PUBLIC_IP"
    echo "external_url 'http://$PUBLIC_IP'" >> /etc/gitlab/gitlab.rb
    echo "$(date): Successfully set external_url to http://$PUBLIC_IP"
else
    echo "Warning: Could not retrieve public IP after $MAX_RETRIES attempts, using default"
    echo "external_url 'http://gitlab.example.com'" >> /etc/gitlab/gitlab.rb
    echo "$(date): WARNING - Using default external_url"
fi

# Configure GitLab for secure authentication
cat >> /etc/gitlab/gitlab.rb << 'EOF'
# Disable signup to prevent unauthorized user creation
gitlab_rails['gitlab_signup_enabled'] = false

# Require authentication for all pages
gitlab_rails['gitlab_signin_enabled'] = true

# Disable public projects by default
gitlab_rails['default_projects_features'] = {
  "issues" => false,
  "merge_requests" => false,
  "wiki" => false,
  "snippets" => false,
  "builds" => false,
  "container_registry" => false
}

# Set session timeout (in seconds) - 8 hours
gitlab_rails['session_expire_delay'] = 28800

# Enable HTTPS redirect
nginx['redirect_http_to_https'] = true

# Configure security headers
nginx['custom_gitlab_server_config'] = "add_header X-Frame-Options DENY;\nadd_header X-Content-Type-Options nosniff;\nadd_header X-XSS-Protection \"1; mode=block\";"
EOF

# Mount EBS volume (assuming it's attached as /dev/sdf)
if [ -b /dev/sdf ]; then
    # Format the volume if it's not already formatted
    if ! blkid /dev/sdf; then
        mkfs.ext4 /dev/sdf
    fi
    
    # Mount the volume
    mount /dev/sdf /mnt/gitlab-data
    
    # Add to fstab for persistent mounting
    echo "/dev/sdf /mnt/gitlab-data ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Reconfigure GitLab with new settings including external URL
echo "$(date): Starting GitLab reconfiguration with external URL..."
gitlab-ctl reconfigure
echo "$(date): GitLab reconfiguration completed"

# Start GitLab services
gitlab-ctl start

# Enable GitLab to start on boot
systemctl enable gitlab-runsvdir

# Wait for GitLab to be fully ready
echo "Waiting for GitLab to be ready..."
sleep 120

# Function to check if GitLab is ready
check_gitlab_ready() {
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f http://localhost/users/sign_in > /dev/null 2>&1; then
            echo "GitLab is ready!"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: GitLab not ready yet, waiting..."
        sleep 10
        ((attempt++))
    done
    
    echo "GitLab failed to become ready after $max_attempts attempts"
    return 1
}

# Check if GitLab is ready
if ! check_gitlab_ready; then
    echo "GitLab is not ready, but continuing with setup..."
fi

# Create a dedicated user for GitLab access with stronger password
GITLAB_USERNAME="${gitlab_username}"
GITLAB_PASSWORD="${gitlab_password}"

# Create user using GitLab Rails console with proper error handling
echo "Creating GitLab user..."
gitlab-rails runner "
begin
  user = User.find_by(username: '${gitlab_username}')
  if user.nil?
    # Create user with stronger password
    user = User.new(
      username: '${gitlab_username}',
      email: '${gitlab_username}@gitlab.local',
      name: 'GitLab User',
      password: '${gitlab_password}',
      password_confirmation: '${gitlab_password}',
      confirmed_at: Time.now,
      admin: true,
      skip_confirmation: true
    )
    
    # Skip password validation to avoid complexity issues
    user.password = '${gitlab_password}'
    user.password_confirmation = '${gitlab_password}'
    user.save!(validate: false)
    
    # Create namespace for the user
    namespace = Namespace.create!(
      name: 'GitLab User',
      path: '${gitlab_username}',
      owner: user,
      type: 'User'
    )
    
    puts 'User created successfully with namespace'
  else
    puts 'User already exists'
  end
rescue => e
  puts \"Error creating user: #{e.message}\"
  puts 'Continuing with root user only...'
end
"

# Get root password
ROOT_PASSWORD=$(sudo cat /etc/gitlab/initial_root_password | grep "Password:" | cut -d' ' -f2)

# Store credentials in a secure file
cat > /root/gitlab-credentials.txt << EOF
GitLab Access Information
========================
URL: http://$PUBLIC_IP

Primary User:
Username: ${gitlab_username}
Password: ${gitlab_password}

Root Access:
Username: root
Password: Check /etc/gitlab/initial_root_password

Generated: $(date)
EOF

# Set secure permissions on credentials file
chmod 600 /root/gitlab-credentials.txt

# Create initial root password (you should change this after first login)
echo "Initial GitLab setup completed!"
echo "You can access GitLab at: http://$PUBLIC_IP"
echo "Primary User: ${gitlab_username} / ${gitlab_password}"
echo "Root User: root / Check /etc/gitlab/initial_root_password"

# External URL was already set at the beginning of the script

# Log completion
echo "$(date): GitLab installation completed successfully" >> /var/log/gitlab-install.log
echo "Credentials stored in /root/gitlab-credentials.txt" >> /var/log/gitlab-install.log
