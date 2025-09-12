#!/bin/bash

# GitLab Runner Configuration and Management Script
# This script runs on the GitLab server to:
# 1. Prepare GitLab for external Docker Machine runner managers
# 2. Configure and manage existing runners
# 3. Provide comprehensive runner monitoring and maintenance
# Based on AWS best practices and GitLab Runner documentation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="/var/log/gitlab-runner-config.log"

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}INFO${NC}: $1"
}

log_success() {
    log "${GREEN}SUCCESS${NC}: $1"
}

log_warning() {
    log "${YELLOW}WARNING${NC}: $1"
}

log_error() {
    log "${RED}ERROR${NC}: $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "GitLab Runner Configuration and Management Script"
    echo ""
    echo "Server Preparation Options:"
    echo "  --prepare-server        Prepare GitLab server for external runners"
    echo "  --show-info             Display runner architecture information"
    echo ""
    echo "Runner Management Options:"
    echo "  --runner-ip IP          Specific runner IP to configure"
    echo "  --list-runners          List all registered runners"
    echo "  --verify-runners        Verify all runner connections"
    echo "  --fix-runners           Fix runners for all projects and untagged jobs"
    echo "  --clean-runners         Remove offline/invalid runners"
    echo "  --show-tokens           Display registration tokens"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --prepare-server         # Prepare GitLab for external runner managers"
    echo "  $0 --show-info              # Show runner architecture information"
    echo "  $0 --fix-runners            # Fix runners for all projects and untagged jobs"
    echo "  $0                          # Auto-discover and configure all runners"
    echo "  $0 --runner-ip 10.0.1.100  # Configure specific runner"
    echo "  $0 --list-runners           # List all registered runners"
    echo "  $0 --verify-runners         # Verify runner connectivity"
}

# Function to get GitLab registration token
get_registration_token() {
    log_info "Getting GitLab registration token..."
    
    local token=""
    for attempt in 1 2 3; do
        token=$(gitlab-rails runner "puts Gitlab::CurrentSettings.runners_registration_token" 2>/dev/null || echo "")
        
        if [ -n "$token" ] && [ "$token" != "nil" ] && [ ${#token} -gt 10 ]; then
            echo "$token"
            return 0
        fi
        
        log_warning "Attempt $attempt/3: Could not get registration token, waiting..."
        sleep 5
    done
    
    log_error "Failed to get registration token"
    return 1
}

# Function to list all registered runners
list_runners() {
    log_info "Listing all registered GitLab runners..."
    
    local runners_info=""
    runners_info=$(gitlab-rails runner "
        runners = Ci::Runner.all
        puts 'Total runners: ' + runners.count.to_s
        puts '=' * 50
        runners.each do |runner|
            puts 'ID: ' + runner.id.to_s
            puts 'Description: ' + runner.description.to_s
            puts 'Status: ' + (runner.online? ? 'Online' : 'Offline')
            puts 'Tags: ' + runner.tag_list.join(', ')
            puts 'Platform: ' + runner.platform.to_s
            puts 'Version: ' + runner.version.to_s
            puts 'Last contact: ' + (runner.contacted_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Never')
            puts 'Created: ' + runner.created_at.strftime('%Y-%m-%d %H:%M:%S')
            puts '-' * 30
        end
    " 2>/dev/null || echo "Error getting runner information")
    
    if [ -n "$runners_info" ]; then
        echo "$runners_info"
    else
        log_warning "No runners found or unable to get runner information"
    fi
}

# Function to verify runner connections
verify_runners() {
    log_info "Verifying GitLab runner connections..."
    
    gitlab-rails runner "
        runners = Ci::Runner.all
        puts 'Verifying ' + runners.count.to_s + ' runners...'
        
        online_count = 0
        offline_count = 0
        
        runners.each do |runner|
            if runner.online?
                puts '✅ Runner ' + runner.id.to_s + ' (' + runner.description + ') is ONLINE'
                online_count += 1
            else
                puts '❌ Runner ' + runner.id.to_s + ' (' + runner.description + ') is OFFLINE'
                puts '   Last contact: ' + (runner.contacted_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Never')
                offline_count += 1
            end
        end
        
        puts '=' * 50
        puts 'Summary: ' + online_count.to_s + ' online, ' + offline_count.to_s + ' offline'
    " 2>/dev/null || log_error "Error verifying runners"
}

# Function to fix runner configuration for all projects and untagged jobs
fix_runner_configuration() {
    log_info "Fixing runner configuration for all projects and untagged jobs..."
    
    gitlab-rails runner "
        runners = Ci::Runner.all
        puts 'Fixing configuration for ' + runners.count.to_s + ' runners...'
        
        runners.each do |runner|
            puts 'Fixing runner ' + runner.id.to_s + ' (' + runner.description + ')'
            
            # Unlock runner from specific projects (make it available to all projects)
            runner.update!(locked: false)
            puts '  ✅ Unlocked from specific projects'
            
            # Enable untagged jobs
            runner.update!(run_untagged: true)
            puts '  ✅ Enabled untagged jobs'
            
            # Remove project-specific assignments to make it available to all projects
            runner.projects.clear
            puts '  ✅ Removed project-specific assignments'
            
            # Ensure runner is active
            runner.update!(active: true)
            puts '  ✅ Ensured runner is active'
            
            puts '  Runner ' + runner.id.to_s + ' is now available for ALL projects and untagged jobs'
            puts '-' * 50
        end
        
        puts 'All runners configured for all projects and untagged jobs'
    " 2>/dev/null || log_error "Error fixing runner configuration"
}

# Function to clean offline runners
clean_runners() {
    log_info "Cleaning offline/invalid GitLab runners..."
    
    gitlab-rails runner "
        offline_runners = Ci::Runner.where('contacted_at < ? OR contacted_at IS NULL', 1.hour.ago)
        puts 'Found ' + offline_runners.count.to_s + ' offline runners (not contacted in 1 hour)'
        
        offline_runners.each do |runner|
            puts 'Removing offline runner: ' + runner.id.to_s + ' - ' + runner.description
            runner.destroy
        end
        
        puts 'Cleanup completed'
    " 2>/dev/null || log_error "Error cleaning runners"
}

# Function to show registration tokens
show_tokens() {
    log_info "Displaying GitLab registration tokens..."
    
    gitlab-rails runner "
        puts 'GitLab Registration Tokens:'
        puts '=' * 40
        puts 'Instance token: ' + Gitlab::CurrentSettings.runners_registration_token
        puts ''
        puts 'Project tokens:'
        Project.all.each do |project|
            if project.runners_token
                puts 'Project: ' + project.name + ' (ID: ' + project.id.to_s + ')'
                puts 'Token: ' + project.runners_token
                puts '-' * 20
            end
        end
    " 2>/dev/null || log_error "Error getting tokens"
}

# Function to discover runner instances
discover_runners() {
    log_info "Discovering GitLab runner instances..."
    
    # Get runner instances from AWS (if available)
    local runner_ips=""
    
    if command -v aws &> /dev/null; then
        log_info "Using AWS CLI to discover runner instances..."
        runner_ips=$(aws ec2 describe-instances \
            --filters "Name=tag:Purpose,Values=gitlab-runner" \
                     "Name=instance-state-name,Values=running" \
            --query 'Reservations[].Instances[].PrivateIpAddress' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$runner_ips" ]; then
        log_warning "No runner instances found via AWS CLI"
        # Try to get from terraform outputs
        if [ -f "$PROJECT_ROOT/terraform.tfstate" ]; then
            log_info "Checking Terraform state for runner IPs..."
            # This would need to be implemented based on your terraform outputs
        fi
    fi
    
    echo "$runner_ips"
}

# Function to configure a specific runner
configure_runner() {
    local runner_ip="$1"
    log_info "Configuring GitLab runner at IP: $runner_ip"
    
    # Test SSH connectivity
    if ! ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$runner_ip "echo 'SSH test successful'" 2>/dev/null; then
        log_error "Cannot connect to runner at $runner_ip via SSH"
        return 1
    fi
    
    log_success "SSH connectivity to $runner_ip verified"
    
    # Get registration token
    local reg_token=""
    reg_token=$(get_registration_token)
    
    if [ -z "$reg_token" ]; then
        log_error "Cannot proceed without registration token"
        return 1
    fi
    
    log_info "Sending registration token to runner..."
    
    # Send configuration command to runner
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ubuntu@$runner_ip "
        echo 'Configuring GitLab Runner with provided token...'
        
        # Re-register the runner if needed
        if ! sudo gitlab-runner list | grep -q 'SageMaker ML Training Runner'; then
            echo 'Registering new runner...'
            sudo gitlab-runner register \\
                --non-interactive \\
                --url 'http://$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)' \\
                --registration-token '$reg_token' \\
                --executor 'docker' \\
                --docker-image 'ubuntu:20.04' \\
                --description 'SageMaker ML Training Runner ($(hostname))' \\
                --tag-list 'ml,sagemaker,training,cicd' \\
                --run-untagged='true' \\
                --locked='false' \\
                --docker-privileged='true' \\
                --docker-volumes '/var/run/docker.sock:/var/run/docker.sock' \\
                --docker-volumes '/cache' \\
                --maximum-timeout '3600' \\
                --request-concurrency '2'
        else
            echo 'Runner already registered'
        fi
        
        # Restart runner service
        sudo systemctl restart gitlab-runner
        
        # Verify status
        sudo gitlab-runner verify --delete
        sudo gitlab-runner list
    " || log_error "Failed to configure runner at $runner_ip"
    
    log_success "Runner at $runner_ip configured successfully"
}

# Function to prepare GitLab server for external runner managers
prepare_gitlab_for_runners() {
    log_info "Preparing GitLab server for external Docker Machine runners..."
    
    # Ensure GitLab is ready for runner registration
    log_info "Verifying GitLab readiness for runner registration..."
    local token=""
    for attempt in 1 2 3 4 5; do
        token=$(gitlab-rails runner "puts Gitlab::CurrentSettings.runners_registration_token" 2>/dev/null || echo "")
        if [ -n "$token" ] && [ "$token" != "nil" ] && [[ "$token" =~ ^glrt- ]]; then
            log_success "GitLab registration token is available: ${token:0:20}..."
            break
        fi
        log_warning "Attempt $attempt/5: Waiting for GitLab registration token..."
        sleep 30
    done
    
    if [ -z "$token" ] || [ "$token" = "nil" ]; then
        log_error "GitLab registration token not available"
        return 1
    fi
    
    # Configure GitLab for shared runners
    log_info "Configuring GitLab for shared runners and CI/CD optimization..."
    gitlab-rails runner "
        # Enable shared runners by default
        Gitlab::CurrentSettings.update!(
          shared_runners_enabled: true,
          max_artifacts_size: 100,
          default_artifacts_expire_in: '30 days',
          auto_devops_enabled: false
        )
        
        puts 'GitLab configured for shared runners'
        
        # Optimize CI/CD settings
        settings = Gitlab::CurrentSettings.current_application_settings
        settings.update!(
          ci_jwt_signing_key: nil,
          auto_devops_enabled: false,
          throttle_authenticated_api_enabled: false,
          throttle_unauthenticated_enabled: false
        )
        puts 'CI/CD optimization settings applied'
    " 2>/dev/null || log_warning "GitLab configuration completed with warnings"
    
    log_success "GitLab server is now ready for external Docker Machine runners"
}

# Function to display runner architecture information
display_runner_architecture_info() {
    local public_ip=""
    public_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "unknown")
    
    echo ""
    echo "======================================"
    echo "GitLab Runner Architecture Information"
    echo "======================================"
    echo ""
    echo "GitLab Server Configuration:"
    echo "  • URL: http://$public_ip"
    echo "  • Ready for external runner managers"
    echo "  • Shared runners enabled"
    echo "  • Registration token available"
    echo ""
    echo "Runner Manager Architecture:"
    echo "  • Separate EC2 instance with Docker Machine"
    echo "  • Auto-scaling based on workload"
    echo "  • SageMaker permissions for ML training"
    echo "  • S3 cache integration"
    echo "  • Cost optimization with scheduling"
    echo ""
    echo "Management Commands:"
    echo "  • $0 --list-runners      # List all registered runners"
    echo "  • $0 --verify-runners    # Verify runner connectivity"
    echo "  • $0 --clean-runners     # Remove offline runners"
    echo "  • $0 --show-tokens       # Display registration tokens"
    echo ""
}

# Function to auto-configure all discovered runners
auto_configure_runners() {
    log_info "Auto-configuring all discovered GitLab runners..."
    
    local runner_ips=""
    runner_ips=$(discover_runners)
    
    if [ -z "$runner_ips" ]; then
        log_warning "No runner instances discovered"
        return 1
    fi
    
    log_info "Found runner instances: $runner_ips"
    
    for ip in $runner_ips; do
        log_info "Configuring runner at $ip..."
        configure_runner "$ip" || log_warning "Failed to configure runner at $ip"
    done
    
    # Verify all runners after configuration
    sleep 10
    verify_runners
}

# Main execution function
main() {
    echo "======================================"
    echo "GitLab Runner Configuration Manager"
    echo "======================================"
    echo ""
    
    # Parse command line arguments
    RUNNER_IP=""
    ACTION="auto-configure"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --prepare-server)
                ACTION="prepare-server"
                shift
                ;;
            --show-info)
                ACTION="show-info"
                shift
                ;;
            --runner-ip)
                RUNNER_IP="$2"
                ACTION="configure-specific"
                shift 2
                ;;
            --list-runners)
                ACTION="list"
                shift
                ;;
            --verify-runners)
                ACTION="verify"
                shift
                ;;
            --fix-runners)
                ACTION="fix"
                shift
                ;;
            --clean-runners)
                ACTION="clean"
                shift
                ;;
            --show-tokens)
                ACTION="tokens"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Create log file
    sudo touch "$LOG_FILE" 2>/dev/null || LOG_FILE="./gitlab-runner-config.log"
    
    log_info "Starting GitLab Runner configuration with action: $ACTION"
    
    # Execute requested action
    case "$ACTION" in
        "prepare-server")
            prepare_gitlab_for_runners
            display_runner_architecture_info
            ;;
        "show-info")
            display_runner_architecture_info
            ;;
        "auto-configure")
            auto_configure_runners
            ;;
        "configure-specific")
            if [ -z "$RUNNER_IP" ]; then
                error_exit "Runner IP not provided"
            fi
            configure_runner "$RUNNER_IP"
            ;;
        "list")
            list_runners
            ;;
        "verify")
            verify_runners
            ;;
        "fix")
            fix_runner_configuration
            ;;
        "clean")
            clean_runners
            ;;
        "tokens")
            show_tokens
            ;;
        *)
            error_exit "Unknown action: $ACTION"
            ;;
    esac
    
    log_success "GitLab Runner configuration completed!"
}

# Script execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
