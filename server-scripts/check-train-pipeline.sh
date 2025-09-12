#!/bin/bash

# GitLab Training Pipeline Checker Script for SageMaker ML Pipeline
# This script checks the status and health of the deployed training pipeline
# Author: Generated for GitLab-SageMaker-CICD-For-ML-Training-and-Hosting
# Date: $(date)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE=".out/cicd_pipeline_check_$(date +%Y%m%d_%H%M%S).log"

# Global variables
GITLAB_IP=""
GITLAB_URL=""
GITLAB_TOKEN=""
PROJECT_ID=""
PROJECT_NAME=""
AWS_ACCOUNT_ID=""
VERBOSE=false
QUICK_MODE=false
CHECK_S3=true
CHECK_SAGEMAKER=true
CHECK_RUNNERS=true
PASSED_GITLAB_TOKEN="" # New variable to store token passed as argument

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

log_debug() {
    if [ "$VERBOSE" = true ]; then
        log "${PURPLE}DEBUG${NC}: $1"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "GitLab Training Pipeline Checker for SageMaker ML Pipeline"
    echo ""
    echo "Options:"
    echo "  --gitlab-ip IP      GitLab server IP (auto-detected if not provided)"
    echo "  --project-id ID     GitLab project ID (auto-detected if not provided)"
    echo "  --project-name NAME GitLab project name (default: training-job-cicd-demo)"
    echo "  --quick             Quick check mode (minimal output, fast execution)"
    echo "  --no-s3            Skip S3 bucket checks"
    echo "  --no-sagemaker     Skip SageMaker checks"
    echo "  --no-runners       Skip GitLab runner checks"
    echo "  --verbose          Enable verbose output"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect all settings"
    echo "  $0 --quick                           # Quick health check"
    echo "  $0 --gitlab-ip 1.2.3.4              # Use specific GitLab IP"
    echo "  $0 --verbose --no-s3                 # Verbose mode, skip S3 checks"
    echo "  $0 --project-id 123 --verbose        # Use specific project ID"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if OpenTofu is available
    if ! command -v tofu &> /dev/null; then
        log_error "OpenTofu is not installed or not in PATH"
        return 1
    fi
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        return 1
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed or not in PATH"
        return 1
    fi
    
    # Check if jq is available (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed - some JSON parsing will be limited"
    fi
    
    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa ]; then
        log_error "SSH key not found at ~/.ssh/id_rsa"
        return 1
    fi
    
    log_success "Prerequisites check passed"
    return 0
}

# Function to get GitLab information
get_gitlab_info() {
    log_info "Getting GitLab information..."
    
    # Get GitLab public IP
    if [ -z "$GITLAB_IP" ]; then
        GITLAB_IP=$(tofu output -raw gitlab_public_ip 2>/dev/null)
        if [ -z "$GITLAB_IP" ]; then
            log_error "Could not get GitLab public IP from OpenTofu outputs"
            return 1
        fi
    fi
    
    GITLAB_URL="http://$GITLAB_IP"
    log_success "GitLab IP: $GITLAB_IP"
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_warning "Could not get AWS Account ID"
    else
        log_success "AWS Account ID: $AWS_ACCOUNT_ID"
    fi
    
    # Set default project name if not provided
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="training-job-cicd-demo"
    fi
    
    return 0
}

# Function to verify GitLab accessibility
verify_gitlab_access() {
    log_info "Verifying GitLab server accessibility..."
    
    # Test HTTP connectivity with better error handling
    log_debug "Testing HTTP connectivity to $GITLAB_URL..."
    HTTP_RESPONSE=$(curl -s -o /dev/null --connect-timeout 15 --max-time 30 -w "%{http_code}" "$GITLAB_URL" || echo "000")
    
    if [ "$HTTP_RESPONSE" = "200" ] || [ "$HTTP_RESPONSE" = "302" ]; then
        log_success "GitLab server is accessible (HTTP $HTTP_RESPONSE)"
    else
        log_error "GitLab server is not accessible at $GITLAB_URL (HTTP response: $HTTP_RESPONSE)"
        log_debug "This might be normal if GitLab is still starting up. Wait a few minutes and try again."
        return 1
    fi
    
    # Test SSH connectivity with timeout and retries
    log_debug "Testing SSH connectivity to ubuntu@$GITLAB_IP..."
    SSH_TEST_RESULT=""
    
    for attempt in 1 2 3; do
        if SSH_TEST_RESULT=$(timeout 20 ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$GITLAB_IP "echo 'SSH test successful'" 2>/dev/null); then
            if [ "$SSH_TEST_RESULT" = "SSH test successful" ]; then
                log_success "SSH connectivity to GitLab server verified"
                return 0
            fi
        fi
        
        log_debug "SSH attempt $attempt failed, retrying..."
        sleep 2
    done
    
    log_error "SSH connectivity to GitLab server failed after 3 attempts"
    log_debug "Check if:"
    log_debug "  • SSH key ~/.ssh/id_rsa exists and has proper permissions"
    log_debug "  • GitLab server security groups allow SSH (port 22)"
    log_debug "  • GitLab server is fully booted and accessible"
    return 1
}

# Function to get GitLab access token
get_gitlab_token() {
    log_info "Getting GitLab access token..."
    
    if [ -n "$PASSED_GITLAB_TOKEN" ]; then
        GITLAB_TOKEN="$PASSED_GITLAB_TOKEN"
        log_success "Using GitLab token provided as argument: ${GITLAB_TOKEN:0:20}..."
        return 0
    fi
    
    # Try to get existing token with timeout
    log_debug "Checking for existing GitLab access tokens..."
    local SSH_COMMAND="sudo gitlab-rails runner \"begin; user = User.find_by(username: 'root'); if user; token = user.personal_access_tokens.active.where('expires_at > ?', Time.current).first; puts 'Token: ' + token.token if token; else; puts 'Error: Root user not found'; end; rescue => e; puts 'Error: ' + e.message; end\""
    TOKEN_OUTPUT=$(timeout 30 ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$GITLAB_IP "$SSH_COMMAND" 2>/dev/null || echo "")
    
    log_debug "SSH command output for existing token: $TOKEN_OUTPUT"
    GITLAB_TOKEN=$(echo "$TOKEN_OUTPUT" | grep "Token:" | cut -d' ' -f2 || echo "")
    
    if [ -z "$GITLAB_TOKEN" ]; then
        log_warning "No active GitLab access token found"
        log_info "Creating temporary token for pipeline check..."
        
        # Use a simpler timestamp approach that works across systems
        TIMESTAMP=$(date +%s)
        TOKEN_NAME="pipeline-check-token-$TIMESTAMP"
        
        log_debug "Creating token: $TOKEN_NAME"
        local CREATE_TOKEN_SSH_COMMAND="sudo gitlab-rails runner \"begin; user = User.find_by(username: 'root'); if user; token = user.personal_access_tokens.create(scopes: ['api', 'read_user', 'read_repository'], name: '$TOKEN_NAME', expires_at: 1.hour.from_now); if token.persisted?; puts 'Token: ' + token.token; else; puts 'Error: Token creation failed - ' + token.errors.full_messages.join(', '); end; else; puts 'Error: Root user not found'; end; rescue => e; puts 'Error: ' + e.message; end\""
        CREATE_TOKEN_OUTPUT=$(timeout 30 ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$GITLAB_IP "$CREATE_TOKEN_SSH_COMMAND" 2>/dev/null || echo "")
        
        log_debug "SSH command output for new token: $CREATE_TOKEN_OUTPUT"
        GITLAB_TOKEN=$(echo "$CREATE_TOKEN_OUTPUT" | grep "Token:" | cut -d' ' -f2 || echo "")
        
        if [ -z "$GITLAB_TOKEN" ]; then
            log_error "Failed to create GitLab access token"
            log_debug "Trying alternative token creation method..."
            
            # Alternative method: try to use existing configuration script approach
            if [ -f "$SCRIPT_DIR/configure-gitlab-cicd" ]; then
                log_debug "Attempting to extract token from configure script..."
                # This is a fallback - we might need to run configure script
                log_warning "Consider running ./server-scripts/configure-gitlab-cicd to set up proper tokens"
            fi
            
            return 1
        fi
    fi
    
    # Validate token format
    if [ ${#GITLAB_TOKEN} -lt 20 ]; then
        log_error "Invalid GitLab token format (too short)"
        return 1
    fi
    
    log_success "GitLab access token obtained: ${GITLAB_TOKEN:0:20}..."
    return 0
}

# Function to get project information
get_project_info() {
    log_info "Getting GitLab project information..."
    
    if [ -z "$PROJECT_ID" ]; then
        # Try to find project by name
        PROJECT_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects?search=$PROJECT_NAME" 2>/dev/null || echo "")
        
        if [ -n "$PROJECT_RESPONSE" ] && echo "$PROJECT_RESPONSE" | grep -q '"id"'; then
            PROJECT_ID=$(echo "$PROJECT_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
            log_success "Found project '$PROJECT_NAME' with ID: $PROJECT_ID"
        else
            # Try to get project ID from GitLab directly via SSH
            log_info "API search failed, trying direct GitLab query..."
            PROJECT_ID=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-rails runner \"project = Project.find_by(name: '$PROJECT_NAME'); puts project.id if project\"" 2>/dev/null || echo "")
            
            if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "nil" ]; then
                log_success "Found project '$PROJECT_NAME' with ID: $PROJECT_ID (via SSH)"
            else
                log_error "Project '$PROJECT_NAME' not found"
                return 1
            fi
        fi
    else
        log_info "Using provided project ID: $PROJECT_ID"
    fi
    
    # Verify project exists and get details
    PROJECT_DETAILS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID" 2>/dev/null || echo "")
    
    if [ -z "$PROJECT_DETAILS" ] || echo "$PROJECT_DETAILS" | grep -q '"message":"404"'; then
        log_error "Project with ID $PROJECT_ID not found or not accessible"
        return 1
    fi
    
    # Extract project name from details
    ACTUAL_PROJECT_NAME=$(echo "$PROJECT_DETAILS" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 || echo "$PROJECT_NAME")
    log_success "Project verified: $ACTUAL_PROJECT_NAME (ID: $PROJECT_ID)"
    
    return 0
}

# Function to check GitLab runners
check_gitlab_runners() {
    if [ "$CHECK_RUNNERS" = false ]; then
        log_info "Skipping GitLab runner checks (--no-runners)"
        return 0
    fi
    
    log_info "Checking GitLab runners..."
    
    # Check if gitlab-runner is installed
    if ! ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "command -v gitlab-runner" &> /dev/null; then
        log_error "GitLab Runner is not installed"
        return 1
    fi
    
    # Get runner status
    RUNNER_STATUS=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-runner status" 2>/dev/null || echo "")
    
    if [ -z "$RUNNER_STATUS" ]; then
        log_error "Failed to get GitLab runner status"
        return 1
    fi
    
    # Count running runners
    RUNNING_RUNNERS=$(echo "$RUNNER_STATUS" | grep -c "is running" || echo "0")
    
    if [ "$RUNNING_RUNNERS" -gt 0 ]; then
        log_success "GitLab runners are running ($RUNNING_RUNNERS runners)"
        
        # Check runner configuration for common issues
        RUNNER_CONFIG=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo cat /etc/gitlab-runner/config.toml" 2>/dev/null || echo "")
        log_debug "GitLab runner config.toml content:
$RUNNER_CONFIG"
        
        if [ -n "$RUNNER_CONFIG" ]; then
            # Check for run_untagged configuration
            if ! echo "$RUNNER_CONFIG" | grep -E "^\[\[runners\]\].*run_untagged = true" &>/dev/null; then
                log_error "RUNNER CONFIGURATION ISSUE: Runners missing 'run_untagged = true' - jobs will be stuck!"
                log_info "Fix: Add 'run_untagged = true' and 'locked = false' to each runner in config.toml"
                return 1
            fi
            
            # Check for locked configuration
            if ! echo "$RUNNER_CONFIG" | grep -E "^\[\[runners\]\].*locked = false" &>/dev/null; then
                log_error "RUNNER CONFIGURATION ISSUE: Runners are 'locked = true' - jobs will be stuck!"
                log_info "Fix: Add 'run_untagged = true' and 'locked = false' to each runner in config.toml"
                return 1
            fi
            
            # Check concurrent setting
            CONCURRENT=$(echo "$RUNNER_CONFIG" | grep "concurrent" | head -1 | grep -o '[0-9]*' || echo "1")
            if [ "$CONCURRENT" -lt 2 ]; then
                log_warning "Low concurrency setting: concurrent = $CONCURRENT (consider increasing for better performance)"
            else
                log_success "Runner concurrency setting: $CONCURRENT"
            fi
            
            log_success "Runner configuration appears correct for untagged jobs"
        fi
        
        # Verify runners are alive
        RUNNER_VERIFY=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-runner verify" 2>/dev/null || echo "")
        if echo "$RUNNER_VERIFY" | grep -q "is alive"; then
            ALIVE_COUNT=$(echo "$RUNNER_VERIFY" | grep -c "is alive" || echo "0")
            log_success "Verified $ALIVE_COUNT runners are alive and connected to GitLab"
        else
            log_warning "Could not verify runner connectivity to GitLab"
        fi
        
        # Get runner list for detailed info
        RUNNER_LIST=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-runner list" 2>/dev/null || echo "")
        if [ -n "$RUNNER_LIST" ]; then
            REGISTERED_COUNT=$(echo "$RUNNER_LIST" | grep -c "Executor=shell" || echo "0")
            log_info "Found $REGISTERED_COUNT registered shell runners"
            if [ "$VERBOSE" = true ]; then
                log_debug "Runner details:"
                echo "$RUNNER_LIST" | while read -r line; do
                    log_debug "  $line"
                done
            fi
        fi
        
        # Check project-specific runner assignments
        log_info "Checking project-specific runner assignments..."
        PROJECT_RUNNERS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/runners" 2>/dev/null || echo "")
        
        if [ -n "$PROJECT_RUNNERS" ] && echo "$PROJECT_RUNNERS" | grep -q '"id"'; then
            PROJECT_RUNNER_COUNT=$(echo "$PROJECT_RUNNERS" | grep -c '"id":' || echo "0")
            log_success "Project has $PROJECT_RUNNER_COUNT runners assigned"
            
            if [ "$VERBOSE" = true ]; then
                log_debug "Project-assigned runners:"
                echo "$PROJECT_RUNNERS" | grep -o '"id":[0-9]*' | while read -r runner_line; do
                    RUNNER_ID=$(echo "$runner_line" | cut -d':' -f2)
                    RUNNER_STATUS=$(echo "$PROJECT_RUNNERS" | grep -A 10 "\"id\":$RUNNER_ID" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
                    RUNNER_ONLINE=$(echo "$PROJECT_RUNNERS" | grep -A 10 "\"id\":$RUNNER_ID" | grep -o '"online":[^,}]*' | head -1 | cut -d':' -f2 || echo "unknown")
                    log_debug "  Runner #$RUNNER_ID: Status=$RUNNER_STATUS, Online=$RUNNER_ONLINE"
                done
            fi
        else
            log_error "❌ CRITICAL: Project has NO RUNNERS ASSIGNED!"
            log_info "💡 This is why jobs are stuck - runners exist but aren't assigned to project"
            log_info "🔧 Solutions:"
            log_info "   1. Enable shared runners for the project (recommended)"
            log_info "   2. Assign specific runners to the project"
            log_info "   3. Configure runners as instance-wide during GitLab installation"
            return 1
        fi
        
        # Check if shared runners are enabled for the project
        PROJECT_DETAILS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID" 2>/dev/null || echo "")
        if [ -n "$PROJECT_DETAILS" ]; then
            SHARED_RUNNERS_ENABLED=$(echo "$PROJECT_DETAILS" | grep -o '"shared_runners_enabled":[^,}]*' | cut -d':' -f2 || echo "false")
            if [ "$SHARED_RUNNERS_ENABLED" = "true" ]; then
                log_success "Shared runners are enabled for this project"
            else
                log_warning "Shared runners are disabled for this project"
                log_info "💡 Either enable shared runners OR assign specific runners to project"
            fi
        fi
    else
        log_warning "No GitLab runners are running"
        return 1
    fi
    
    return 0
}


# Function to check CI/CD variables
check_cicd_variables() {
    log_info "Checking CI/CD variables..."
    
    # Get project variables
    VARIABLES_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/variables" 2>/dev/null || echo "")
    
    log_debug "Raw CI/CD variables API response: $VARIABLES_RESPONSE"
    
    if [ -z "$VARIABLES_RESPONSE" ]; then
        log_error "Failed to retrieve CI/CD variables"
        return 1
    fi
    
    # Check for required variables
    REQUIRED_VARS=("AWS_DEFAULT_REGION" "AWS_ACCOUNT_ID" "SAGEMAKER_ROLE_ARN" "S3_BUCKET" "GITLAB_ARTIFACTS_BUCKET" "GITLAB_RELEASES_BUCKET")
    
    local missing_vars=()
    local found_vars=()
    
    for var in "${REQUIRED_VARS[@]}"; do
        if echo "$VARIABLES_RESPONSE" | grep -q "\"key\":\"$var\""; then
            found_vars+=("$var")
            log_debug "Found variable: $var"
        else
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#found_vars[@]} -gt 0 ]; then
        log_success "Found ${#found_vars[@]} CI/CD variables: ${found_vars[*]}"
    fi
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_warning "Missing CI/CD variables: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}

# Function to get GitLab CI/CD YAML content
get_gitlab_ci_content() {
    log_info "Attempting to retrieve .gitlab-ci.yml content from GitLab API..."
    GITLAB_CI_CONTENT=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/files/.gitlab-ci.yml/raw?ref=main")
    
    if echo "$GITLAB_CI_CONTENT" | grep -q "404"; then
        log_error "Failed to get .gitlab-ci.yml content from GitLab API (404 Not Found or similar). Response: $GITLAB_CI_CONTENT"
        GITLAB_CI_CONTENT="" # Clear content if 404
        return 1
    fi
    
    if [ -z "$GITLAB_CI_CONTENT" ]; then
        log_error "Retrieved empty .gitlab-ci.yml content."
        return 1
    fi
    log_success "Successfully retrieved .gitlab-ci.yml content."
    return 0
}

# Function to check GitLab CI/CD YAML configuration
check_yaml_configuration() {
    log_info "Checking GitLab CI/CD YAML configuration..."
    
    # Get the GitLab CI/CD content first
    if ! get_gitlab_ci_content; then
        log_warning "Cannot check YAML configuration without .gitlab-ci.yml content."
        return 1
    fi
    
    # Try to lint the YAML configuration via API
    LINT_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "Content-Type: application/json" \
        --data '{"content": "'$(echo "$GITLAB_CI_CONTENT" | sed 's/\n/\\n/g' | sed 's/"/\"/g')'"}' "$GITLAB_URL/api/v4/projects/$PROJECT_ID/ci/lint" 2>/dev/null || echo "")
    
    if [ -n "$LINT_RESPONSE" ] && echo "$LINT_RESPONSE" | grep -q '"status":"valid"'; then
        log_success "GitLab CI/CD YAML configuration is valid."
    else
        log_error "GitLab CI/CD YAML configuration is NOT valid."
        if [ -n "$LINT_RESPONSE" ]; then
            log_debug "Linting errors: $LINT_RESPONSE"
        fi
        # Continue with other checks, but mark as error
    fi
    
    if [ -n "$GITLAB_CI_CONTENT" ]; then
        log_success "Found .gitlab-ci.yml file in repository"
        log_debug ".gitlab-ci.yml content:
$GITLAB_CI_CONTENT"
        log_debug "Checking for common YAML issues..."
        
        # Check for common YAML syntax issues that cause "nested array" errors
        if echo "$GITLAB_CI_CONTENT" | grep -q "script:.*\$(.*)" && echo "$GITLAB_CI_CONTENT" | grep -q "echo.*\$("; then
            log_error "YAML SYNTAX ERROR: Shell substitution \$() found in script sections - this causes 'nested array' errors"
            log_info "Fix: Replace echo \"var: \$(command)\" with echo \"var: \$VARIABLE\" or use simple commands"
        fi
        
        # Check for problematic shell substitutions
        if echo "$GITLAB_CI_CONTENT" | grep -q "before_script.*\$("; then
            log_warning "Potential shell substitution issue in before_script section"
        fi
        
        # Check for overly nested script structures
        if echo "$GITLAB_CI_CONTENT" | grep -E "script:.*- \\|.*if.*then.*else.*fi" | wc -l | grep -q "[3-9]"; then
            log_warning "Complex nested script structures detected - may cause YAML parsing issues"
        fi
        
        # Check for missing stages
        if ! echo "$GITLAB_CI_CONTENT" | grep -qE "^stages:"; then
            log_warning "No 'stages' section found in .gitlab-ci.yml"
        fi
        
        # Check for emoji or special characters that might cause issues
        if echo "$GITLAB_CI_CONTENT" | grep -q "[✅❌]"; then
            log_warning "Emoji characters detected in YAML - may cause parsing issues"
        fi
        
        log_debug "YAML configuration checked for common syntax issues"
    else
        log_warning "Could not retrieve .gitlab-ci.yml file content"
        return 1
    fi
    
    return 0
}

# Function to list all pipelines with details
list_all_pipelines() {
    log_info "Listing all pipelines for debugging..."
    
    # Get all pipelines (more than default)
    PIPELINES_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?per_page=10&sort=desc" 2>/dev/null || echo "")
    
    if [ -z "$PIPELINES_RESPONSE" ]; then
        log_error "Failed to retrieve pipeline information"
        return 1
    fi
    
    # Check if there are any pipelines
    if ! echo "$PIPELINES_RESPONSE" | grep -q '"id"'; then
        log_warning "No pipelines found for this project"
        return 1
    fi
    
    # Count total pipelines
    PIPELINE_COUNT=$(echo "$PIPELINES_RESPONSE" | grep -c '"id":' || echo "0")
    log_info "Found $PIPELINE_COUNT pipelines in project"
    
    # List all pipelines with details
    if [ "$VERBOSE" = true ]; then
        log_info "Pipeline details:"
        echo "$PIPELINES_RESPONSE" | grep -o '"id":[0-9]*' | while read -r pipeline_line; do
            PIPELINE_ID=$(echo "$pipeline_line" | cut -d':' -f2)
            
            # Extract details for this specific pipeline
            PIPELINE_BLOCK=$(echo "$PIPELINES_RESPONSE" | sed -n "/$pipeline_line/,/},{/p" | head -20)
            
            PIPELINE_STATUS=$(echo "$PIPELINE_BLOCK" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
            PIPELINE_REF=$(echo "$PIPELINE_BLOCK" | grep -o '"ref":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
            PIPELINE_SHA=$(echo "$PIPELINE_BLOCK" | grep -o '"sha":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
            PIPELINE_CREATED=$(echo "$PIPELINE_BLOCK" | grep -o '"created_at":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
            
            log_info "  Pipeline #$PIPELINE_ID: Status=$PIPELINE_STATUS, Ref=$PIPELINE_REF, SHA=${PIPELINE_SHA:0:8}, Created=$PIPELINE_CREATED"
        done
    fi
    
    return 0
}

# Function to describe latest pipeline in detail
describe_latest_pipeline() {
    log_info "Analyzing latest pipeline in detail..."
    
    # Initialize variables to avoid unbound variable errors
    LATEST_PIPELINE_ID=""
    LATEST_PIPELINE_STATUS=""
    LATEST_PIPELINE_REF=""
    LATEST_PIPELINE_SHA=""
    
    # Get latest pipeline
    LATEST_PIPELINE_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?per_page=1" 2>/dev/null || echo "")
    
    if [ -z "$LATEST_PIPELINE_RESPONSE" ] || ! echo "$LATEST_PIPELINE_RESPONSE" | grep -q '"id"'; then
        log_warning "No latest pipeline found"
        return 1
    fi
    
    # Extract pipeline details
    LATEST_PIPELINE_ID=$(echo "$LATEST_PIPELINE_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    LATEST_PIPELINE_STATUS=$(echo "$LATEST_PIPELINE_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    LATEST_PIPELINE_REF=$(echo "$LATEST_PIPELINE_RESPONSE" | grep -o '"ref":"[^"]*"' | head -1 | cut -d'"' -f4)
    LATEST_PIPELINE_SHA=$(echo "$LATEST_PIPELINE_RESPONSE" | grep -o '"sha":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    log_info "=== LATEST PIPELINE ANALYSIS ==="
    log_info "Pipeline ID: $LATEST_PIPELINE_ID"
    log_info "Status: $LATEST_PIPELINE_STATUS"
    log_info "Branch/Ref: $LATEST_PIPELINE_REF"
    log_info "Commit SHA: ${LATEST_PIPELINE_SHA:0:12}"
    log_info "Pipeline URL: $GITLAB_URL/root/$PROJECT_NAME/-/pipelines/$LATEST_PIPELINE_ID"
    
    # Get detailed pipeline information
    PIPELINE_DETAILS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$LATEST_PIPELINE_ID" 2>/dev/null || echo "")
    
    if [ -n "$PIPELINE_DETAILS" ]; then
        PIPELINE_CREATED=$(echo "$PIPELINE_DETAILS" | grep -o '"created_at":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        PIPELINE_UPDATED=$(echo "$PIPELINE_DETAILS" | grep -o '"updated_at":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        PIPELINE_DURATION=$(echo "$PIPELINE_DETAILS" | grep -o '"duration":[0-9]*' | cut -d':' -f2 || echo "0")
        
        log_info "Created: $PIPELINE_CREATED"
        log_info "Last updated: $PIPELINE_UPDATED"
        log_info "Duration: ${PIPELINE_DURATION}s"
        
        # Check for pipeline-level errors
        if echo "$PIPELINE_DETAILS" | grep -q '"yaml_errors"'; then
            YAML_ERRORS=$(echo "$PIPELINE_DETAILS" | grep -o '"yaml_errors":\[[^]]*\]' || echo "")
            log_error "YAML ERRORS DETECTED: $YAML_ERRORS"
        fi
    fi
    
    return 0
}

# Function to list and describe all jobs in latest pipeline
describe_pipeline_jobs() {
    local pipeline_id="$1"
    
    log_info "Analyzing all jobs in latest pipeline..."
    
    if [ -z "$pipeline_id" ]; then
        log_warning "No pipeline ID provided for job analysis"
        return 1
    fi
    
    # Get all jobs for the latest pipeline
    JOBS_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$pipeline_id/jobs" 2>/dev/null || echo "")
    
    if [ -z "$JOBS_RESPONSE" ] || ! echo "$JOBS_RESPONSE" | grep -q '"name"'; then
        log_warning "No jobs found in latest pipeline"
        return 1
    fi
    
    # Count jobs
    JOB_COUNT=$(echo "$JOBS_RESPONSE" | grep -c '"name":' || echo "0")
    log_info "=== PIPELINE JOBS ANALYSIS ($JOB_COUNT jobs) ==="
    
    # Get available runners for comparison
    AVAILABLE_RUNNERS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/runners" 2>/dev/null || echo "")
    RUNNER_COUNT=$(echo "$AVAILABLE_RUNNERS" | grep -c '"id":' || echo "0")
    log_info "Project has $RUNNER_COUNT assigned runners"
    
    # Process each job
    echo "$JOBS_RESPONSE" | grep -o '"id":[0-9]*' | while read -r job_line; do
        JOB_ID=$(echo "$job_line" | cut -d':' -f2)
        
        # Get detailed job information
        JOB_DETAILS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$JOB_ID" 2>/dev/null || echo "")
        
        if [ -n "$JOB_DETAILS" ]; then
            JOB_NAME=$(echo "$JOB_DETAILS" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
            JOB_STATUS=$(echo "$JOB_DETAILS" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
            JOB_STAGE=$(echo "$JOB_DETAILS" | grep -o '"stage":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
            JOB_CREATED=$(echo "$JOB_DETAILS" | grep -o '"created_at":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
            JOB_STARTED=$(echo "$JOB_DETAILS" | grep -o '"started_at":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "null")
            JOB_RUNNER_ID=$(echo "$JOB_DETAILS" | grep -o '"runner":{"id":[0-9]*' | cut -d':' -f3 || echo "null")
            
            log_info "--- Job: $JOB_NAME (ID: $JOB_ID) ---"
            log_info "  Status: $JOB_STATUS"
            log_info "  Stage: $JOB_STAGE"
            log_info "  Created: $JOB_CREATED"
            log_info "  Started: $JOB_STARTED"
            log_info "  Runner ID: $JOB_RUNNER_ID"
            log_info "  Job URL: $GITLAB_URL/root/$PROJECT_NAME/-/jobs/$JOB_ID"
            
            # Analyze job status
            case "$JOB_STATUS" in
                "pending")
                    log_warning "  🟡 Job is PENDING - waiting for runner assignment"
                    if [ "$JOB_RUNNER_ID" = "null" ]; then
                        log_error "  ❌ NO RUNNER ASSIGNED - this is the problem!"
                        log_info "  💡 Possible causes:"
                        log_info "     - No runners available for this project"
                        log_info "     - Runners not configured for untagged jobs"
                        log_info "     - Runner capacity exhausted"
                    fi
                    ;;
                "running")
                    log_success "  🟢 Job is RUNNING on runner $JOB_RUNNER_ID"
                    ;;
                "success")
                    log_success "  ✅ Job COMPLETED SUCCESSFULLY"
                    ;;
                "failed")
                    log_error "  ❌ Job FAILED"
                    # Try to get failure reason
                    if echo "$JOB_DETAILS" | grep -q '"failure_reason"'; then
                        FAILURE_REASON=$(echo "$JOB_DETAILS" | grep -o '"failure_reason":"[^"]*"' | cut -d'"' -f4)
                        log_error "  📋 Failure reason: $FAILURE_REASON"
                    fi
                    ;;
                "canceled"|"cancelled")
                    log_warning "  🔴 Job was CANCELED"
                    ;;
                "stuck")
                    log_error "  🚫 Job is STUCK"
                    log_info "  💡 Usually means no runners available or runner configuration issue"
                    ;;
                *)
                    log_info "  ⚪ Job status: $JOB_STATUS"
                    ;;
            esac
            
            # Get job trace/logs for failed or pending jobs
            if [ "$JOB_STATUS" = "failed" ] || [ "$JOB_STATUS" = "pending" ] && [ "$VERBOSE" = true ]; then
                log_debug "  📋 Getting job trace for debugging..."
                JOB_TRACE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/jobs/$JOB_ID/trace" 2>/dev/null | tail -10 || echo "")
                if [ -n "$JOB_TRACE" ]; then
                    log_debug "  Last 10 lines of job trace:"
                    echo "$JOB_TRACE" | while IFS= read -r line; do
                        log_debug "    $line"
                    done
                fi
            fi
            
            echo ""
        fi
    done
    
    return 0
}

# Function to check pipeline status (enhanced)
check_pipeline_status() {
    log_info "Checking pipeline status..."
    
    # Initialize pipeline variables to avoid unbound variable errors
    LATEST_PIPELINE_ID=""
    LATEST_PIPELINE_STATUS=""
    LATEST_PIPELINE_REF=""
    LATEST_PIPELINE_SHA=""
    
    # First list all pipelines
    list_all_pipelines
    echo ""
    
    # Then describe the latest pipeline
    describe_latest_pipeline
    echo ""
    
    # Finally analyze all jobs in detail (if we have a pipeline ID)
    if [ -n "$LATEST_PIPELINE_ID" ]; then
        describe_pipeline_jobs "$LATEST_PIPELINE_ID"
    else
        log_warning "No pipeline ID available for job analysis"
    fi
    
    # Determine overall pipeline health
    if [ -n "$LATEST_PIPELINE_STATUS" ]; then
        case "$LATEST_PIPELINE_STATUS" in
            "success")
                log_success "Latest pipeline completed successfully"
                return 0
                ;;
            "failed")
                log_error "Latest pipeline failed - check job details above"
                return 1
                ;;
            "running"|"pending")
                log_warning "Latest pipeline is still $LATEST_PIPELINE_STATUS - check job assignments above"
                return 0
                ;;
            *)
                log_warning "Latest pipeline status: $LATEST_PIPELINE_STATUS"
                return 0
                ;;
        esac
    else
        log_warning "Could not determine pipeline status"
        return 1
    fi
}

# Function to check S3 buckets
check_s3_buckets() {
    if [ "$CHECK_S3" = false ]; then
        log_info "Skipping S3 bucket checks (--no-s3)"
        return 0
    fi
    
    log_info "Checking S3 buckets..."
    
    # Get S3 bucket names from OpenTofu
    ARTIFACTS_BUCKET=$(tofu output -raw gitlab_artifacts_bucket_name 2>/dev/null || echo "")
    RELEASES_BUCKET=$(tofu output -raw gitlab_releases_bucket_name 2>/dev/null || echo "")
    
    local bucket_checks_passed=0
    local total_buckets=0
    
    # Check artifacts bucket
    if [ -n "$ARTIFACTS_BUCKET" ]; then
        total_buckets=$((total_buckets + 1))
        if aws s3api head-bucket --bucket "$ARTIFACTS_BUCKET" &>/dev/null; then
            log_success "Artifacts bucket accessible: $ARTIFACTS_BUCKET"
            
            # Check bucket contents
            OBJECT_COUNT=$(aws s3 ls "s3://$ARTIFACTS_BUCKET" --recursive 2>/dev/null | wc -l || echo "0")
            log_info "Artifacts bucket contains $OBJECT_COUNT objects"
            
            bucket_checks_passed=$((bucket_checks_passed + 1))
        else
            log_error "Artifacts bucket not accessible: $ARTIFACTS_BUCKET"
        fi
    else
        log_warning "Artifacts bucket name not found in OpenTofu outputs"
    fi
    
    # Check releases bucket
    if [ -n "$RELEASES_BUCKET" ]; then
        total_buckets=$((total_buckets + 1))
        if aws s3api head-bucket --bucket "$RELEASES_BUCKET" &>/dev/null; then
            log_success "Releases bucket accessible: $RELEASES_BUCKET"
            
            # Check bucket contents
            OBJECT_COUNT=$(aws s3 ls "s3://$RELEASES_BUCKET" --recursive 2>/dev/null | wc -l || echo "0")
            log_info "Releases bucket contains $OBJECT_COUNT objects"
            
            bucket_checks_passed=$((bucket_checks_passed + 1))
        else
            log_error "Releases bucket not accessible: $RELEASES_BUCKET"
        fi
    else
        log_warning "Releases bucket name not found in OpenTofu outputs"
    fi
    
    if [ $total_buckets -eq 0 ]; then
        log_warning "No S3 buckets configured"
        return 1
    elif [ $bucket_checks_passed -eq $total_buckets ]; then
        log_success "All S3 buckets are accessible"
        return 0
    else
        log_warning "Some S3 buckets are not accessible ($bucket_checks_passed/$total_buckets)"
        return 1
    fi
}

# Function to check SageMaker resources
check_sagemaker_resources() {
    if [ "$CHECK_SAGEMAKER" = false ]; then
        log_info "Skipping SageMaker checks (--no-sagemaker)"
        return 0
    fi
    
    log_info "Checking SageMaker resources..."
    
    # Check SageMaker execution role
    SAGEMAKER_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/SageMakerExecutionRole"
    
    if aws iam get-role --role-name SageMakerExecutionRole &>/dev/null; then
        log_success "SageMaker execution role exists: $SAGEMAKER_ROLE_ARN"
    else
        log_error "SageMaker execution role not found: $SAGEMAKER_ROLE_ARN"
        return 1
    fi
    
    # Check for recent training jobs
    log_info "Checking recent SageMaker training jobs..."
    
    TRAINING_JOBS=$(aws sagemaker list-training-jobs --max-items 10 --query 'TrainingJobSummaries[?contains(TrainingJobName, `training-job-cicd-demo`)].{Name:TrainingJobName,Status:TrainingJobStatus,CreationTime:CreationTime}' --output table 2>/dev/null || echo "")
    
    if [ -n "$TRAINING_JOBS" ] && echo "$TRAINING_JOBS" | grep -q "training-job-cicd-demo"; then
        log_success "Found recent training jobs:"
        echo "$TRAINING_JOBS" | while read -r line; do
            log_info "  $line"
        done
    else
        log_warning "No recent training jobs found for this project"
    fi
    
    # Check for model packages
    log_info "Checking SageMaker model packages..."
    
    MODEL_PACKAGES=$(aws sagemaker list-model-packages --max-items 10 --query 'ModelPackageSummaryList[?contains(ModelPackageName, `ml-models`)].{Name:ModelPackageName,Status:ModelPackageStatus,CreationTime:CreationTime}' --output table 2>/dev/null || echo "")
    
    if [ -n "$MODEL_PACKAGES" ] && echo "$MODEL_PACKAGES" | grep -q "ml-models"; then
        log_success "Found model packages:"
        echo "$MODEL_PACKAGES" | while read -r line; do
            log_info "  $line"
        done
    else
        log_warning "No model packages found for this project"
    fi
    
    return 0
}

# Function to check project repository
check_project_repository() {
    log_info "Checking project repository..."
    
    # Get repository information
    REPO_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/tree" 2>/dev/null || echo "")
    
    log_debug "Raw repository tree API response: $REPO_RESPONSE"
    
    if [ -z "$REPO_RESPONSE" ]; then
        log_error "Failed to retrieve repository information"
        return 1
    fi
    
    # Check for key files
    KEY_FILES=(".gitlab-ci.yml" "train.py" "create_zip_package.py" "send_notification.py")
    
    local found_files=()
    local missing_files=()
    
    for file in "${KEY_FILES[@]}"; do
        if echo "$REPO_RESPONSE" | grep -q "\"name\":\"$file\""; then
            found_files+=("$file")
            log_debug "Found file: $file"
        else
            missing_files+=("$file")
        fi
    done
    
    if [ ${#found_files[@]} -gt 0 ]; then
        log_success "Found ${#found_files[@]} key files: ${found_files[*]}"
    fi
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        log_warning "Missing files: ${missing_files[*]}"
        return 1
    fi
    
    return 0
}

# Function to perform quick health check
quick_health_check() {
    log_info "Performing quick health check..."
    
    local quick_checks_passed=0
    local quick_total_checks=0
    
    # Essential checks only
    local quick_checks=(
        "GitLab Info" "get_gitlab_info"
        "GitLab Access" "verify_gitlab_access"
        "Project Info" "get_project_info"
        "Pipeline Status" "check_pipeline_status"
    )
    
    for ((i=0; i<${#quick_checks[@]}; i+=2)); do
        local check_name="${quick_checks[i]}"
        local check_func="${quick_checks[i+1]}"
        
        quick_total_checks=$((quick_total_checks + 1))
        
        if [ "$VERBOSE" = true ]; then
            log_info "Running quick check: $check_name"
        fi
        
        if $check_func; then
            quick_checks_passed=$((quick_checks_passed + 1))
        fi
    done
    
    # Quick summary
    echo ""
    echo "🔍 Quick Training Pipeline Health Check"
    echo "======================================"
    echo ""
    
    if [ $quick_checks_passed -eq $quick_total_checks ]; then
        echo -e "${GREEN}✅ Pipeline Status: HEALTHY${NC}"
        echo ""
        echo "Quick Summary:"
        echo "  • GitLab server is accessible"
        echo "  • Training pipeline is working"
        echo "  • All essential components are operational"
        echo ""
        echo "For detailed information, run:"
        echo "  $0 --verbose"
        return 0
    else
        echo -e "${RED}❌ Pipeline Status: ISSUES DETECTED${NC}"
        echo ""
        echo "Quick Summary:"
        echo "  • Some pipeline components may have issues"
        echo "  • Check the detailed report below"
        echo ""
        echo "For detailed information, run:"
        echo "  $0 --verbose"
        return 1
    fi
}

# Function to generate comprehensive report
generate_report() {
    local overall_status=$1
    local checks_passed=$2
    local total_checks=$3
    
    echo ""
    echo "======================================"
    echo "Training Pipeline Health Report"
    echo "======================================"
    echo ""
    
    if [ "$overall_status" = "healthy" ]; then
        echo -e "${GREEN}✅ Overall Status: HEALTHY${NC}"
    elif [ "$overall_status" = "warning" ]; then
        echo -e "${YELLOW}⚠️ Overall Status: WARNING${NC}"
    else
        echo -e "${RED}❌ Overall Status: UNHEALTHY${NC}"
    fi
    
    echo ""
    echo "Check Summary:"
    echo "  • Checks Passed: $checks_passed/$total_checks"
    echo "  • Pass Rate: $(( (checks_passed * 100) / total_checks ))%"
    echo ""
    
    echo "GitLab Details:"
    echo "  • URL: $GITLAB_URL"
    echo "  • Project: $PROJECT_NAME (ID: $PROJECT_ID)"
    echo "  • Pipeline URL: $GITLAB_URL/root/$PROJECT_NAME/-/pipelines"
    echo ""
    
    echo "S3 Buckets:"
    echo "  • Artifacts: $(tofu output -raw gitlab_artifacts_bucket_name 2>/dev/null || echo 'N/A')"
    echo "  • Releases: $(tofu output -raw gitlab_releases_bucket_name 2>/dev/null || echo 'N/A')"
    echo ""
    
    echo "Next Steps:"
    if [ "$overall_status" = "healthy" ]; then
        echo "  • Pipeline is working correctly"
        echo "  • Monitor pipeline execution in GitLab UI"
        echo "  • Check S3 buckets for artifacts"
    else
        echo "  • Review failed checks above"
        echo "  • Run configure script: ./server-scripts/configure-gitlab-cicd"
        echo "  • Re-run launch script: ./server-scripts/launch-train-job.sh"
    fi
    
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
}

# Main execution function
main() {
    if [ "$QUICK_MODE" = true ]; then
        echo "🔍 Quick Training Pipeline Health Check"
        echo "======================================"
        echo ""
    else
        echo "======================================"
        echo "GitLab Training Pipeline Checker"
        echo "======================================"
        echo ""
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --gitlab-ip)
                GITLAB_IP="$2"
                shift 2
                ;;
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --quick)
                QUICK_MODE=true
                shift
                ;;
            --no-s3)
                CHECK_S3=false
                shift
                ;;
            --no-sagemaker)
                CHECK_SAGEMAKER=false
                shift
                ;;
            --no-runners)
                CHECK_RUNNERS=false
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --gitlab-token)
                PASSED_GITLAB_TOKEN="$2"
                shift 2
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
    
    # Create .out directory if it doesn't exist
    mkdir -p .out
    
    # Start logging
    if [ "$QUICK_MODE" = true ]; then
        log_info "Starting quick training pipeline health check..."
    else
        log_info "Starting comprehensive training pipeline health check..."
    fi
    log_info "Configuration: S3=$CHECK_S3, SageMaker=$CHECK_SAGEMAKER, Runners=$CHECK_RUNNERS, Verbose=$VERBOSE, Quick=$QUICK_MODE"
    
    # Run quick mode or comprehensive mode
    if [ "$QUICK_MODE" = true ]; then
        # Quick mode - essential checks only
        if quick_health_check; then
            exit 0
        else
            exit 1
        fi
    else
        # Comprehensive mode - all checks
        # Initialize counters
        local checks_passed=0
        local total_checks=0
        
        # Run all checks
        local checks=(
            "Prerequisites" "check_prerequisites"
            "GitLab Info" "get_gitlab_info"
            "GitLab Access" "verify_gitlab_access"
            "GitLab Token" "get_gitlab_token"
            "Project Info" "get_project_info"
            "GitLab Runners" "check_gitlab_runners"
            "CI/CD Variables" "check_cicd_variables"
            "YAML Configuration" "check_yaml_configuration"
            "Pipeline Status" "check_pipeline_status"
            "S3 Buckets" "check_s3_buckets"
            "SageMaker Resources" "check_sagemaker_resources"
            "Project Repository" "check_project_repository"
        )
        
        for ((i=0; i<${#checks[@]}; i+=2)); do
            local check_name="${checks[i]}"
            local check_func="${checks[i+1]}"
            
            total_checks=$((total_checks + 1))
            
            log_info "Running check: $check_name"
            if $check_func; then
                checks_passed=$((checks_passed + 1))
            fi
            echo ""
        done
        
        # Determine overall status
        local overall_status
        if [ $checks_passed -eq $total_checks ]; then
            overall_status="healthy"
        elif [ $checks_passed -ge $((total_checks * 3 / 4)) ]; then
            overall_status="warning"
        else
            overall_status="unhealthy"
        fi
        
        # Generate report
        generate_report "$overall_status" "$checks_passed" "$total_checks"
        
        # Exit with appropriate code
        if [ "$overall_status" = "healthy" ]; then
            log_success "Training pipeline health check completed successfully!"
            exit 0
        elif [ "$overall_status" = "warning" ]; then
            log_warning "Training pipeline has some issues but is mostly functional"
            exit 1
        else
            log_error "Training pipeline has significant issues"
            exit 2
        fi
    fi
}

# Script execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
