#!/bin/bash

# GitLab Installation Script for Ubuntu 22.04
# This script installs GitLab CE on an EC2 instance

set -e

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

# Set GitLab external URL
echo "external_url '${gitlab_external_url}'" >> /etc/gitlab/gitlab.rb

# Configure GitLab to use the attached EBS volume for data
echo "git_data_dirs({
  \"default\" => {
    \"path\" => \"/mnt/gitlab-data\"
  }
})" >> /etc/gitlab/gitlab.rb

# Create directory for GitLab data on EBS volume
mkdir -p /mnt/gitlab-data
chown git:git /mnt/gitlab-data

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
    
    # Set proper ownership
    chown git:git /mnt/gitlab-data
fi

# Reconfigure GitLab with new settings
gitlab-ctl reconfigure

# Start GitLab services
gitlab-ctl start

# Enable GitLab to start on boot
systemctl enable gitlab-runsvdir

# Create initial root password (you should change this after first login)
echo "Initial GitLab setup completed!"
echo "You can access GitLab at: ${gitlab_external_url}"
echo "Default username: root"
echo "Please check the GitLab logs for the initial root password:"
echo "sudo cat /etc/gitlab/initial_root_password"

# Log completion
echo "$(date): GitLab installation completed successfully" >> /var/log/gitlab-install.log
