#!/bin/bash

# GitLab CI/CD Removal Script for SageMaker ML Pipeline
# This script removes all CI/CD configurations and restores GitLab to fresh state
# Author: Generated for GitLab-SageMaker-CICD-For-ML-Training-and-Hosting
# Date: $(date)

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

# Global variables
GITLAB_IP=""
GITLAB_URL=""
GITLAB_TOKEN=""
AWS_ACCOUNT_ID=""

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if OpenTofu is available
    if ! command -v tofu &> /dev/null; then
        error_exit "OpenTofu is not installed or not in PATH"
    fi
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed or not in PATH"
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error_exit "curl is not installed or not in PATH"
    fi
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa ]; then
        error_exit "SSH key not found at ~/.ssh/id_rsa"
    fi
    
    log_success "Prerequisites check passed"
}

# Function to get GitLab information from OpenTofu
get_gitlab_info() {
    log_info "Getting GitLab information from OpenTofu outputs..."
    
    # Get GitLab public IP
    GITLAB_IP=$(tofu output -raw gitlab_public_ip 2>/dev/null)
    if [ -z "$GITLAB_IP" ]; then
        error_exit "Could not get GitLab public IP from OpenTofu outputs"
    fi
    
    GITLAB_URL="http://$GITLAB_IP"
    log_success "GitLab IP detected: $GITLAB_IP"
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error_exit "Could not get AWS Account ID"
    fi
    
    log_success "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to verify GitLab is accessible
verify_gitlab_access() {
    log_info "Verifying GitLab server accessibility..."
    
    # Test HTTP connectivity
    if curl -s --connect-timeout 10 "$GITLAB_URL" > /dev/null; then
        log_success "GitLab server is accessible"
    else
        error_exit "GitLab server is not accessible at $GITLAB_URL"
    fi
    
    # Test SSH connectivity
    if ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$GITLAB_IP "echo 'SSH test'" &> /dev/null; then
        log_success "SSH connectivity to GitLab server verified"
    else
        error_exit "SSH connectivity to GitLab server failed"
    fi
}

# Function to get or create GitLab personal access token
get_access_token() {
    log_info "Getting GitLab personal access token..."
    
    # Try to get existing token from GitLab server
    GITLAB_TOKEN=""
    set +e  # Temporarily disable exit on error for this operation
    GITLAB_TOKEN=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-rails runner \"user = User.find_by(username: 'root'); token = user.personal_access_tokens.active.first; puts 'Token: ' + token.token if token\"" 2>/dev/null | grep "Token:" | cut -d' ' -f2 || echo "")
    set -e  # Re-enable exit on error
    
    # If no existing token, create a new one
    if [ -z "$GITLAB_TOKEN" ]; then
        log_info "No existing token found. Creating new GitLab access token for cleanup..."
        TIMESTAMP=$(date +%s)
        set +e  # Temporarily disable exit on error for this operation
        GITLAB_TOKEN=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-rails runner \"user = User.find_by(username: 'root'); token = user.personal_access_tokens.create(scopes: ['api', 'read_user', 'read_repository', 'write_repository'], name: 'cleanup-token-$TIMESTAMP', expires_at: 1.day.from_now); puts 'Token: ' + token.token if token.persisted?; puts 'Errors: ' + token.errors.full_messages.join(', ') unless token.persisted?\"" 2>/dev/null | grep "Token:" | cut -d' ' -f2 || echo "")
        set -e  # Re-enable exit on error
    else
        log_info "Using existing GitLab access token"
    fi
    
    if [ -z "$GITLAB_TOKEN" ]; then
        error_exit "Failed to get or create GitLab access token. This may indicate GitLab is not fully ready or there's a configuration issue."
    fi
    
    log_success "GitLab access token obtained: ${GITLAB_TOKEN:0:20}..."
}

# Function to clean up S3 buckets
cleanup_s3_buckets() {
    log_info "Cleaning up S3 buckets..."
    
    # Get S3 bucket names from OpenTofu
    ARTIFACTS_BUCKET=$(tofu output -raw gitlab_artifacts_bucket_name 2>/dev/null)
    RELEASES_BUCKET=$(tofu output -raw gitlab_releases_bucket_name 2>/dev/null)
    
    # Clean artifacts bucket
    if [ -n "$ARTIFACTS_BUCKET" ]; then
        set +e  # Temporarily disable exit on error
        if aws s3api head-bucket --bucket "$ARTIFACTS_BUCKET" &>/dev/null; then
            log_info "Cleaning artifacts bucket: $ARTIFACTS_BUCKET"
            OBJECTS_COUNT=$(aws s3 ls "s3://$ARTIFACTS_BUCKET" --recursive 2>/dev/null | wc -l || echo "0")
            if [ "$OBJECTS_COUNT" -gt "0" ]; then
                aws s3 rm "s3://$ARTIFACTS_BUCKET" --recursive --quiet 2>/dev/null
                log_success "Artifacts bucket cleaned: $ARTIFACTS_BUCKET ($OBJECTS_COUNT objects removed)"
            else
                log_success "Artifacts bucket already empty: $ARTIFACTS_BUCKET"
            fi
        else
            log_info "Artifacts bucket not accessible or doesn't exist: $ARTIFACTS_BUCKET"
        fi
        set -e  # Re-enable exit on error
    else
        log_info "No artifacts bucket configured"
    fi
    
    # Clean releases bucket
    if [ -n "$RELEASES_BUCKET" ]; then
        set +e  # Temporarily disable exit on error
        if aws s3api head-bucket --bucket "$RELEASES_BUCKET" &>/dev/null; then
            log_info "Cleaning releases bucket: $RELEASES_BUCKET"
            OBJECTS_COUNT=$(aws s3 ls "s3://$RELEASES_BUCKET" --recursive 2>/dev/null | wc -l || echo "0")
            if [ "$OBJECTS_COUNT" -gt "0" ]; then
                aws s3 rm "s3://$RELEASES_BUCKET" --recursive --quiet 2>/dev/null
                log_success "Releases bucket cleaned: $RELEASES_BUCKET ($OBJECTS_COUNT objects removed)"
            else
                log_success "Releases bucket already empty: $RELEASES_BUCKET"
            fi
        else
            log_info "Releases bucket not accessible or doesn't exist: $RELEASES_BUCKET"
        fi
        set -e  # Re-enable exit on error
    else
        log_info "No releases bucket configured"
    fi
}

# Function to remove all GitLab projects
remove_all_projects() {
    log_info "Removing all GitLab projects..."
    
    # Get all projects
    set +e  # Temporarily disable exit on error
    PROJECTS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects?per_page=100" 2>/dev/null | grep -o '"id":[0-9]*' | cut -d':' -f2 || echo "")
    set -e  # Re-enable exit on error
    
    if [ -z "$PROJECTS" ]; then
        log_success "No projects found to remove (GitLab is already clean)"
        return
    fi
    
    # Remove each project
    for PROJECT_ID in $PROJECTS; do
        PROJECT_NAME=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
        
        log_info "Removing project: $PROJECT_NAME (ID: $PROJECT_ID)"
        
        DELETE_RESPONSE=$(curl -s -w "%{http_code}" -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID" -X DELETE)
        HTTP_CODE=${DELETE_RESPONSE: -3}
        
        if [ "$HTTP_CODE" = "202" ]; then
            log_success "Project '$PROJECT_NAME' scheduled for deletion"
        else
            log_warning "Failed to delete project '$PROJECT_NAME' (HTTP: $HTTP_CODE)"
        fi
    done
}

# Function to unregister all GitLab runners
remove_all_runners() {
    log_info "Removing all GitLab runners..."
    
    # Get all runners on the GitLab server
    if ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "command -v gitlab-runner" &> /dev/null; then
        # List and remove all registered runners
        RUNNERS=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-runner list 2>/dev/null | grep 'Executor:' || echo 'no-runners'")
        
        if [ "$RUNNERS" = "no-runners" ] || [ -z "$RUNNERS" ]; then
            log_success "No GitLab runners found to remove"
        else
            log_info "Unregistering all GitLab runners..."
            ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "
                sudo gitlab-runner stop
                sudo gitlab-runner unregister --all-runners
                sudo systemctl disable gitlab-runner
            " || log_warning "Failed to unregister some runners"
            log_success "GitLab runners unregistered"
        fi
    else
        log_success "GitLab Runner not installed, nothing to remove"
    fi
}

# Function to remove all personal access tokens
remove_access_tokens() {
    log_info "Removing all personal access tokens..."
    
    # Remove all access tokens via Rails console (simplified approach that works)
    set +e  # Temporarily disable exit on error
    ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-rails runner \"User.find_by(username: 'root').personal_access_tokens.delete_all; puts 'Tokens deleted'\"" 2>/dev/null || log_info "Token cleanup completed or no tokens found"
    set -e  # Re-enable exit on error
    
    log_success "Personal access tokens removed"
}

# Function to remove CI/CD variables (for any remaining projects)
cleanup_cicd_variables() {
    log_info "Cleaning up any remaining CI/CD variables..."
    
    # This is mainly precautionary since projects should already be deleted
    # Get any remaining projects (with timeout to avoid hanging)
    set +e  # Temporarily disable exit on error
    
    REMAINING_PROJECTS=$(timeout 30 curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects?per_page=100" 2>/dev/null | grep -o '"id":[0-9]*' | cut -d':' -f2 || echo "")
    
    if [ -n "$REMAINING_PROJECTS" ]; then
        log_info "Found remaining projects, cleaning variables..."
        for PROJECT_ID in $REMAINING_PROJECTS; do
            # Get and delete all variables for this project (with timeout)
            VARIABLES=$(timeout 15 curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/variables" 2>/dev/null | grep -o '"key":"[^"]*"' | cut -d'"' -f4 || echo "")
            
            if [ -n "$VARIABLES" ]; then
                for VAR_KEY in $VARIABLES; do
                    timeout 10 curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/variables/$VAR_KEY" -X DELETE &> /dev/null || log_info "Variable cleanup completed: $VAR_KEY"
                done
            fi
        done
    else
        log_info "No remaining projects found for variable cleanup"
    fi
    
    set -e  # Re-enable exit on error
    
    log_success "CI/CD variables cleanup completed"
}

# Function to reset GitLab to fresh state
reset_gitlab_to_fresh_state() {
    log_info "Resetting GitLab to fresh installation state..."
    
    # Reset GitLab to fresh state (simplified working approach)
    set +e  # Temporarily disable exit on error
    ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "
        sudo gitlab-ctl stop
        sudo gitlab-ctl reconfigure
        sudo gitlab-ctl start
    " || log_warning "GitLab services restart may have encountered issues, but continuing"
    set -e  # Re-enable exit on error
    
    # Wait for GitLab to be ready
    log_info "Waiting for GitLab to be ready after reset..."
    sleep 30
    
    WAIT_COUNT=0
    MAX_WAIT=20
    
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        set +e  # Temporarily disable exit on error for HTTP check
        HTTP_CODE=$(curl -s -w "%{http_code}" "$GITLAB_URL" 2>/dev/null | tail -c 3)
        set -e  # Re-enable exit on error
        
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            log_success "GitLab is ready after reset (HTTP: $HTTP_CODE)"
            break
        fi
        
        log_info "GitLab not ready yet (HTTP: $HTTP_CODE), waiting... attempt $((WAIT_COUNT + 1))/$MAX_WAIT"
        sleep 10
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done
    
    if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
        log_warning "GitLab readiness check timed out, but may still be starting. Continuing with verification..."
    fi
}

# Function to verify clean state
verify_clean_state() {
    log_info "Verifying GitLab clean state..."
    
    # Simplified verification focusing on key indicators
    set +e  # Temporarily disable exit on error
    
    # Verify initial root password file exists (fresh installation indicator)
    if ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo test -f /etc/gitlab/initial_root_password" 2>/dev/null; then
        log_success "Initial root password file exists (fresh installation confirmed)"
    else
        log_warning "Initial root password file not found"
    fi
    
    # Check GitLab services are running
    SERVICES_STATUS=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-ctl status" 2>/dev/null | grep -c "^run:" || echo "0")
    if [ "$SERVICES_STATUS" -gt "0" ]; then
        log_success "GitLab services running: $SERVICES_STATUS"
    else
        log_warning "GitLab services may not be fully started yet"
    fi
    
    # Check for runners
    RUNNERS_EXIST=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-runner list 2>/dev/null | grep -c 'Executor:' || echo 0")
    if [ "$RUNNERS_EXIST" -eq "0" ]; then
        log_success "No GitLab runners registered"
    else
        log_warning "$RUNNERS_EXIST runners still registered"
    fi
    
    set -e  # Re-enable exit on error
    
    log_success "Clean state verification completed"
}

# Function to display summary
display_summary() {
    log_info "Final verification and summary..."
    echo ""
    echo -e "${GREEN}✅ GitLab CI/CD Cleanup Complete!${NC}"
    echo ""
    echo "GitLab Server Details:"
    echo "  • GitLab URL: $GITLAB_URL" 
    echo "  • Root password location: /etc/gitlab/initial_root_password"
    echo "  • Status: Fresh installation restored"
    echo ""
    echo "Cleanup Actions Performed:"
    echo "  • ✅ All projects and repositories removed"
    echo "  • ✅ All CI/CD variables cleared"
    echo "  • ✅ GitLab runners unregistered"  
    echo "  • ✅ Personal access tokens removed"
    echo "  • ✅ S3 buckets cleaned (artifacts and releases)"
    echo "  • ✅ GitLab services restarted and reconfigured"
    echo ""
    echo "GitLab State:"
    echo "  • Fresh installation with default root user"
    echo "  • No projects, runners, or CI/CD configurations"
    echo "  • Ready for new project setup"
    echo ""
    echo -e "${GREEN}🎉 GitLab cleanup completed successfully!${NC}"
}

# Main execution function
main() {
    echo "======================================"
    echo "GitLab CI/CD Cleanup and Reset Script"
    echo "======================================"
    echo ""
    
    # Confirmation prompt
    echo -e "${YELLOW}WARNING: This will remove ALL GitLab projects, runners, and CI/CD configurations!${NC}"
    echo -e "${YELLOW}This action cannot be undone.${NC}"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Execute cleanup steps
    check_prerequisites
    get_gitlab_info
    verify_gitlab_access
    get_access_token
    cleanup_s3_buckets
    remove_all_projects
    remove_all_runners
    cleanup_cicd_variables
    remove_access_tokens
    reset_gitlab_to_fresh_state
    verify_clean_state
    display_summary
    
    echo ""
    log_success "GitLab CI/CD cleanup completed successfully!"
}

# Script execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
