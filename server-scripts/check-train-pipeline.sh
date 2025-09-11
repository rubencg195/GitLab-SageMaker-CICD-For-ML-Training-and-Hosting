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
    HTTP_RESPONSE=$(curl -s --connect-timeout 15 --max-time 30 -w "%{http_code}" "$GITLAB_URL" 2>/dev/null | tail -n1)
    
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
    
    # Try to get existing token with timeout
    log_debug "Checking for existing GitLab access tokens..."
    GITLAB_TOKEN=$(timeout 30 ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$GITLAB_IP "sudo gitlab-rails runner \"
        begin
            user = User.find_by(username: 'root')
            if user
                token = user.personal_access_tokens.active.where('expires_at > ?', Time.current).first
                puts 'Token: ' + token.token if token
            else
                puts 'Error: Root user not found'
            end
        rescue => e
            puts 'Error: ' + e.message
        end\"" 2>/dev/null | grep "Token:" | cut -d' ' -f2 || echo "")
    
    if [ -z "$GITLAB_TOKEN" ]; then
        log_warning "No active GitLab access token found"
        log_info "Creating temporary token for pipeline check..."
        
        # Use a simpler timestamp approach that works across systems
        TIMESTAMP=$(date +%s)
        TOKEN_NAME="pipeline-check-token-$TIMESTAMP"
        
        log_debug "Creating token: $TOKEN_NAME"
        GITLAB_TOKEN=$(timeout 30 ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$GITLAB_IP "sudo gitlab-rails runner \"
            begin
                user = User.find_by(username: 'root')
                if user
                    token = user.personal_access_tokens.create(
                        scopes: ['api', 'read_user', 'read_repository'],
                        name: '$TOKEN_NAME',
                        expires_at: 1.hour.from_now
                    )
                    if token.persisted?
                        puts 'Token: ' + token.token
                    else
                        puts 'Error: Token creation failed - ' + token.errors.full_messages.join(', ')
                    end
                else
                    puts 'Error: Root user not found'
                end
            rescue => e
                puts 'Error: ' + e.message
            end\"" 2>/dev/null | grep "Token:" | cut -d' ' -f2 || echo "")
        
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
        
        # Get runner list
        RUNNER_LIST=$(ssh -i ~/.ssh/id_rsa ubuntu@$GITLAB_IP "sudo gitlab-runner list" 2>/dev/null || echo "")
        if [ -n "$RUNNER_LIST" ]; then
            log_debug "Runner details:"
            echo "$RUNNER_LIST" | while read -r line; do
                log_debug "  $line"
            done
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

# Function to check for YAML configuration errors
check_yaml_configuration() {
    log_info "Checking GitLab CI/CD YAML configuration..."
    
    # Try to lint the YAML configuration via API
    LINT_RESPONSE=$(curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "Content-Type: application/json" \
        --data '{"content": ""}' "$GITLAB_URL/api/v4/projects/$PROJECT_ID/ci/lint" 2>/dev/null || echo "")
    
    # Also check for common YAML configuration issues by getting project files
    GITLAB_CI_CONTENT=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/files/.gitlab-ci.yml/raw?ref=master" 2>/dev/null || \
        curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/files/.gitlab-ci.yml/raw?ref=main" 2>/dev/null || echo "")
    
    if [ -n "$GITLAB_CI_CONTENT" ]; then
        log_success "Found .gitlab-ci.yml file in repository"
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
        if ! echo "$GITLAB_CI_CONTENT" | grep -q "stages:"; then
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

# Function to check pipeline status
check_pipeline_status() {
    log_info "Checking pipeline status..."
    
    # Get latest pipelines
    PIPELINES_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?per_page=5" 2>/dev/null || echo "")
    
    if [ -z "$PIPELINES_RESPONSE" ]; then
        log_error "Failed to retrieve pipeline information"
        return 1
    fi
    
    # Check if there are any pipelines
    if ! echo "$PIPELINES_RESPONSE" | grep -q '"id"'; then
        log_warning "No pipelines found for this project"
        return 1
    fi
    
    # Check for recent pipeline failures with specific error messages
    LATEST_PIPELINE_STATUS=$(echo "$PIPELINES_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ "$LATEST_PIPELINE_STATUS" = "failed" ]; then
        LATEST_PIPELINE_ID=$(echo "$PIPELINES_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        log_warning "Latest pipeline failed (ID: $LATEST_PIPELINE_ID)"
        
        # Try to get detailed failure information
        PIPELINE_JOBS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$LATEST_PIPELINE_ID/jobs" 2>/dev/null || echo "")
        
        if echo "$PIPELINE_JOBS" | grep -q "yaml invalid\|Unable to create pipeline"; then
            log_error "YAML configuration error detected in latest pipeline"
            log_info "Common causes: Invalid YAML syntax, shell substitution issues, or configuration nesting problems"
            return 1
        fi
    fi
    
    # Get latest pipeline details
    LATEST_PIPELINE_ID=$(echo "$PIPELINES_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    LATEST_PIPELINE_STATUS=$(echo "$PIPELINES_RESPONSE" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    LATEST_PIPELINE_REF=$(echo "$PIPELINES_RESPONSE" | grep -o '"ref":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    log_info "Latest pipeline: ID=$LATEST_PIPELINE_ID, Status=$LATEST_PIPELINE_STATUS, Ref=$LATEST_PIPELINE_REF"
    
    # Get detailed pipeline information
    PIPELINE_DETAILS=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$LATEST_PIPELINE_ID" 2>/dev/null || echo "")
    
    if [ -n "$PIPELINE_DETAILS" ]; then
        PIPELINE_URL=$(echo "$PIPELINE_DETAILS" | grep -o '"web_url":"[^"]*"' | cut -d'"' -f4 || echo "")
        PIPELINE_CREATED=$(echo "$PIPELINE_DETAILS" | grep -o '"created_at":"[^"]*"' | cut -d'"' -f4 || echo "")
        
        log_info "Pipeline URL: $PIPELINE_URL"
        log_info "Pipeline created: $PIPELINE_CREATED"
    fi
    
    # Get pipeline jobs
    JOBS_RESPONSE=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$LATEST_PIPELINE_ID/jobs" 2>/dev/null || echo "")
    
    if [ -n "$JOBS_RESPONSE" ] && echo "$JOBS_RESPONSE" | grep -q '"name"'; then
        log_info "Pipeline jobs:"
        echo "$JOBS_RESPONSE" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read -r job_name; do
            job_status=$(echo "$JOBS_RESPONSE" | grep -A 5 "\"name\":\"$job_name\"" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
            log_info "  • $job_name: $job_status"
        done
    fi
    
    # Determine overall pipeline health
    case "$LATEST_PIPELINE_STATUS" in
        "success")
            log_success "Latest pipeline completed successfully"
            return 0
            ;;
        "failed")
            log_error "Latest pipeline failed"
            return 1
            ;;
        "running"|"pending")
            log_warning "Latest pipeline is still $LATEST_PIPELINE_STATUS"
            return 0
            ;;
        *)
            log_warning "Latest pipeline status: $LATEST_PIPELINE_STATUS"
            return 0
            ;;
    esac
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
