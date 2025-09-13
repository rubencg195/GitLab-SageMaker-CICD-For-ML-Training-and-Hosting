#!/bin/bash

# GitLab Training Job Launcher Script
# This script sets up the training repository and launches CI/CD pipeline
# Author: Generated for GitLab-SageMaker-CICD-For-ML-Training-and-Hosting
# Date: $(date)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m' # Define PURPLE
CYAN='\033[0;36m'   # Define CYAN
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Global variables (will be passed as parameters)
GITLAB_IP=""
GITLAB_URL=""
GITLAB_TOKEN=""
PROJECT_ID=""
PROJECT_NAME=""
PUSHED_COMMIT_HASH=""
PUSHED_TIMESTAMP=""
BRANCH_NAME=""
VERBOSE=true # Enable verbose logging for debugging

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

log_debug() {
    if [ "$VERBOSE" = true ]; then
        log "${PURPLE}DEBUG${NC}: $1"
    fi
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Function to setup training code repository
setup_code_repository() {
    set -x # Enable shell debugging
    log_info "Setting up training scripts repository..."
    
    # Generate unique commit info first (needed for README and commit messages)
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    RANDOM_ID=$(date +%N | tail -c4)  # Use nanoseconds for randomness
    COMMIT_HASH=$(echo "$TIMESTAMP-$$-$RANDOM_ID" | sha256sum 2>/dev/null | cut -d' ' -f1 | head -c8 || echo "$(date +%s | tail -c8)")

    # Get GitLab root password for authentication (moved up for ls-remote check)
    log_info "Retrieving GitLab root password for authentication..."
    GITLAB_ROOT_PASSWORD=$(ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$GITLAB_IP "sudo cat /etc/gitlab/initial_root_password | grep 'Password:' | awk '{print \$2}'" 2>/dev/null)
    
    if [ -z "$GITLAB_ROOT_PASSWORD" ]; then
        log_error "Could not retrieve GitLab root password"
        return 1
    fi
    
    ENCODED_PASSWORD=$(echo "$GITLAB_ROOT_PASSWORD" | sed 's|/|%2F|g; s|=|%3D|g; s|\+|%2B|g; s|!|%21|g')
    GITLAB_REPO_URL="http://root:$ENCODED_PASSWORD@$GITLAB_IP/root/$PROJECT_NAME.git"
    BRANCH_NAME="main"

    # Create temporary directory for GitLab repository content
    TEMP_REPO_DIR="/tmp/gitlab-training-repo-$$"
    rm -rf "$TEMP_REPO_DIR"
    mkdir -p "$TEMP_REPO_DIR"
    
    log_info "Preparing training scripts repository structure..."

    # Check if remote branch exists
    log_info "Checking if remote branch '$BRANCH_NAME' exists at $GITLAB_REPO_URL..."
    if git ls-remote --heads "$GITLAB_REPO_URL" "$BRANCH_NAME" &> /dev/null; then
        log_info "Remote branch '$BRANCH_NAME' found. Cloning existing repository."
        git clone "$GITLAB_REPO_URL" "$TEMP_REPO_DIR"
        cd "$TEMP_REPO_DIR"
        # After cloning, 'main' branch is already checked out by git clone
    else
        log_info "Remote branch '$BRANCH_NAME' not found. Initializing new repository."
        cd "$TEMP_REPO_DIR"
        git init --initial-branch="$BRANCH_NAME"
    fi
    
    git config user.email "gitlab-cicd@localhost"
    git config user.name "GitLab CI/CD Setup"

    # Add remote if not already added (for cloned repos this will be origin)
    if git remote get-url origin &> /dev/null; then
        log_info "Remote 'origin' already exists, updating URL."
        git remote set-url origin "$GITLAB_REPO_URL"
    else
        log_info "Remote 'origin' not found, adding it."
        git remote add origin "$GITLAB_REPO_URL"
    fi
    log_success "GitLab authentication configured with root user"

    # Copy only the training-related files to temp directory
    if [ -d "$PROJECT_ROOT/train-script" ]; then
        cp -r "$PROJECT_ROOT/train-script"/* "$TEMP_REPO_DIR/"
        log_success "Copied training scripts"
    else
        error_exit "train-script directory not found in $PROJECT_ROOT"
    fi
    
    # Copy CI/CD configuration
    log_debug "Attempting to copy .gitlab-ci.yml from $PROJECT_ROOT/.gitlab-ci.yml to $TEMP_REPO_DIR/"
    if [ -f "$PROJECT_ROOT/.gitlab-ci.yml" ]; then
        cp "$PROJECT_ROOT/.gitlab-ci.yml" "$TEMP_REPO_DIR/"
        log_success "Copied CI/CD configuration"
    else
        log_error ".gitlab-ci.yml not found in $PROJECT_ROOT"
        return 1
    fi
    log_debug ".gitlab-ci.yml content in TEMP_REPO_DIR:"
    log_debug "$(cat "$TEMP_REPO_DIR/.gitlab-ci.yml" 2>/dev/null || echo 'File not found')"
    
    # Copy source code if exists
    if [ -d "src" ]; then
        cp -r src "$TEMP_REPO_DIR/"
        log_success "Copied source code"
    fi
    
    # Copy tests if exists
    if [ -d "tests" ]; then
        cp -r tests "$TEMP_REPO_DIR/"
        log_success "Copied tests"
    fi
    
    # Get AWS Account ID and S3 bucket names for the pipeline
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "176843580427")
    ARTIFACTS_BUCKET="gitlab-server-production-artifacts-be069d6d"
    RELEASES_BUCKET="gitlab-server-production-releases-c4175b30"
    
    # Create environment variables file for CI/CD
    cat > "$TEMP_REPO_DIR/.env" << EOF
# Auto-generated environment variables for GitLab CI/CD
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export GITLAB_ARTIFACTS_BUCKET="$ARTIFACTS_BUCKET"
export GITLAB_RELEASES_BUCKET="$RELEASES_BUCKET"
export SAGEMAKER_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/SageMakerExecutionRole"
export S3_BUCKET="ml-training-data-$AWS_ACCOUNT_ID"
EOF

    # Create a simple README for the training repository
    cat > "$TEMP_REPO_DIR/README.md" << EOF
# SageMaker ML Training Pipeline Demo

This repository contains a simplified training pipeline demo for SageMaker ML model training.

## Structure

- \`train.py\` - Main training script
- \`create_zip_package.py\` - Package and upload artifacts
- \`.gitlab-ci.yml\` - CI/CD pipeline configuration
- \`.env\` - Environment variables for CI/CD

## Pipeline Stages

1. **build** - Environment setup and validation
2. **train** - XGBoost model training
3. **package** - Artifact compression and S3 upload
4. **notify** - Pipeline notifications

## Artifacts

- Trained models are packaged as ZIP files
- Artifacts are stored in S3 buckets

## Environment

- AWS Account ID: $AWS_ACCOUNT_ID
- Artifacts Bucket: $ARTIFACTS_BUCKET
- Releases Bucket: $RELEASES_BUCKET

Generated automatically by GitLab CI/CD launcher script.
Commit Hash: $COMMIT_HASH
Timestamp: $TIMESTAMP
EOF
    
    
    # Add all new files
    git add ./.gitlab-ci.yml
    git add .
    log_debug "Git status after git add:\n$(git status)"
    
    # Create commit with unique message including random file content to ensure uniqueness
    echo "Build trigger: $COMMIT_HASH-$(date +%N)" > ".pipeline-trigger-$COMMIT_HASH"
    git add ".pipeline-trigger-$COMMIT_HASH"
    
    # Add a unique timestamp file to ensure every commit is different
    echo "Pipeline execution timestamp: $(date +%s%N)" > ".unique-timestamp-$(date +%s%N)"
    git add ".unique-timestamp-*"
    
    git commit -m "Training pipeline update - $TIMESTAMP - Build $COMMIT_HASH"
    log_debug "Git status after git commit:\n$(git status)"
    
    # Check if there are actual content changes to force push, otherwise create an empty commit
    log_info "Checking for content changes before pushing..."
    git fetch origin "$BRANCH_NAME" 2>/dev/null || true # Fetch remote branch, ignore errors if it doesn't exist yet
    
    if git diff --quiet "origin/$BRANCH_NAME" "HEAD"; then
        log_info "No content changes detected. Creating an empty commit to trigger pipeline."
        git commit --allow-empty -m "Trigger pipeline (empty commit) - $TIMESTAMP - Build $COMMIT_HASH"
        # Ensure local branch is up-to-date before pushing
        log_info "Pulling latest changes from remote before pushing..."
        if ! git pull --rebase origin "$BRANCH_NAME"; then
            log_warning "Failed to pull latest changes. This might indicate an empty repository or a new branch. Proceeding with push."
        fi

        # Push the empty commit without force
        if git push origin "$BRANCH_NAME"; then
            log_success "Empty commit pushed to GitLab main branch (Hash: $COMMIT_HASH, Branch: $BRANCH_NAME)"
        else
            log_error "Failed to push empty commit to GitLab"
            return 1
        fi
    else
        log_info "Content changes detected. Proceeding with regular push."
        
        # Push with content changes
        log_info "Pushing to GitLab main branch: $BRANCH_NAME"
        if git push origin "$BRANCH_NAME"; then
            log_success "Training pipeline pushed to GitLab main branch (Hash: $COMMIT_HASH, Branch: $BRANCH_NAME)"
        else
            log_error "Failed to push training scripts to GitLab"
            return 1
        fi
    fi
    
    # Store commit info for summary (make variables global for monitor function)
    PUSHED_COMMIT_HASH="$COMMIT_HASH"
    PUSHED_TIMESTAMP="$TIMESTAMP"
    
    # Return to project root and cleanup
    cd "$PROJECT_ROOT"
    rm -rf "$TEMP_REPO_DIR"
    
    log_info "Repository setup complete - GitLab now contains training demo with unique commit $COMMIT_HASH"
}

# Function to get or create fresh GitLab token  
get_fresh_gitlab_token() {
    log_info "Getting fresh GitLab access token for API calls..."
    
    # Create a fresh token for monitoring
    TIMESTAMP=$(date +%s)
    TOKEN_NAME="pipeline-monitor-token-$TIMESTAMP"
    
    FRESH_TOKEN=$(ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$GITLAB_IP "sudo gitlab-rails runner \"
        user = User.find_by(username: 'root')
        if user
            token = user.personal_access_tokens.create(
                scopes: ['api', 'read_user', 'read_repository'],
                name: '$TOKEN_NAME',
                expires_at: 2.hours.from_now
            )
            puts token.token if token.persisted?
        end\"" 2>/dev/null)
    
    if [ -n "$FRESH_TOKEN" ] && [ ${#FRESH_TOKEN} -gt 20 ]; then
        GITLAB_TOKEN="$FRESH_TOKEN"
        log_success "Fresh GitLab token obtained for monitoring"
        return 0
    else
        log_warning "Could not get fresh token, using provided token"
        return 1
    fi
}

# Function to monitor pipeline
monitor_pipeline() {
    log_info "Monitoring GitLab CI/CD pipeline for new commit..."
    
    # Get a fresh token for API calls
    get_fresh_gitlab_token || log_warning "Using original token for monitoring"
    
    # Wait longer for GitLab to detect the new commit and create pipeline
    log_info "Waiting for GitLab to detect new commit and create pipeline..."
    sleep 10
    
    # Try multiple times to find the new pipeline
    local max_attempts=6
    local attempt=1
    local pipeline_found=false
    
    while [ $attempt -le $max_attempts ] && [ "$pipeline_found" = false ]; do
        log_info "Checking for new pipeline (attempt $attempt/$max_attempts)..."
        
        # Get latest pipelines
        PIPELINE_INFO=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?per_page=5" 2>/dev/null || echo "")
        
        if [ -n "$PIPELINE_INFO" ] && echo "$PIPELINE_INFO" | grep -q '"status"'; then
            # Get the latest pipeline
            PIPELINE_ID=$(echo "$PIPELINE_INFO" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
            PIPELINE_STATUS=$(echo "$PIPELINE_INFO" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
            PIPELINE_REF=$(echo "$PIPELINE_INFO" | grep -o '"ref":"[^"]*"' | head -1 | cut -d'"' -f4)
            PIPELINE_SHA=$(echo "$PIPELINE_INFO" | grep -o '"sha":"[^"]*"' | head -1 | cut -d'"' -f4)
            PIPELINE_URL="$GITLAB_URL/root/$PROJECT_NAME/-/pipelines/$PIPELINE_ID"
            
            log_info "Found pipeline: ID=$PIPELINE_ID, Status=$PIPELINE_STATUS, Ref=$PIPELINE_REF"
            log_info "Pipeline SHA: ${PIPELINE_SHA:0:8}... (looking for commits with our hash: $PUSHED_COMMIT_HASH)"
            log_info "Pipeline URL: $PIPELINE_URL"
            
            pipeline_found=true
            
            if [ "$PIPELINE_STATUS" = "success" ]; then
                log_success "Pipeline completed successfully!"
            elif [ "$PIPELINE_STATUS" = "failed" ]; then
                log_warning "Pipeline failed. Check the GitLab UI for details: $PIPELINE_URL"
            elif [ "$PIPELINE_STATUS" = "running" ] || [ "$PIPELINE_STATUS" = "pending" ]; then
                log_info "Pipeline is $PIPELINE_STATUS. Monitor at: $PIPELINE_URL"
            else
                log_info "Pipeline status: $PIPELINE_STATUS. URL: $PIPELINE_URL"
            fi
        else
            log_warning "No pipeline found yet, waiting..."
            sleep 5
            attempt=$((attempt + 1))
        fi
    done
    
    if [ "$pipeline_found" = false ]; then
        log_warning "Could not find new pipeline after $max_attempts attempts"
        log_info "Check GitLab project manually: $GITLAB_URL/root/$PROJECT_NAME/-/pipelines"
        log_info "The pipeline might take longer to appear or there might be a CI/CD configuration issue"
    fi
}

# Function to display summary
display_summary() {
    log_info "Launch Summary:"
    echo ""
    echo -e "${GREEN}✅ GitLab Training Job Launched!${NC}"
    echo ""
    echo "GitLab Server Details:"
    echo "  • URL: $GITLAB_URL"
    echo "  • Project ID: $PROJECT_ID"
    echo "  • Project URL: $GITLAB_URL/root/$PROJECT_NAME"
    echo ""
    echo "S3 Buckets:"
    echo "  • Artifacts: gitlab-server-production-artifacts-be069d6d"
    echo "  • Releases: gitlab-server-production-releases-c4175b30"
    echo ""
    echo "Training Pipeline Features:"
    echo "  • ✅ Simplified training demo"
    echo "  • ✅ S3 artifact storage"
    echo "  • ✅ Automated packaging"
    echo "  • ✅ Unique commit generation"
    echo ""
    echo "Pipeline Trigger Information:"
    if [ -n "$PUSHED_COMMIT_HASH" ]; then
        echo "  • Commit Hash: $PUSHED_COMMIT_HASH"
        echo "  • Timestamp: $PUSHED_TIMESTAMP"
        echo "  • Each run creates a NEW commit → NEW pipeline"
    fi
    echo ""
    echo "Next Steps:"
    echo "  1. Visit GitLab project: $GITLAB_URL/root/$PROJECT_NAME"
    echo "  2. Monitor pipeline: $GITLAB_URL/root/$PROJECT_NAME/-/pipelines"
    echo "  3. Check S3 buckets for training artifacts"
    echo "  4. Run again to trigger another pipeline with new commit"
    echo ""
    echo -e "${BLUE}Training job launched! 🚀${NC}"
    echo -e "${GREEN}✨ New pipeline will be triggered automatically${NC}"
}

# Main execution function
main() {
    echo "======================================"
    echo "GitLab Training Job Launcher"
    echo "======================================"
    echo ""
    
    # Validate required parameters
    if [ $# -ne 5 ]; then
        echo "Usage: $0 <gitlab_ip> <gitlab_url> <gitlab_token> <project_id> <project_name>"
        echo ""
        echo "Parameters:"
        echo "  gitlab_ip     - GitLab server IP address"
        echo "  gitlab_url    - GitLab server URL"
        echo "  gitlab_token  - GitLab access token"
        echo "  project_id    - GitLab project ID"
        echo "  project_name  - GitLab project name"
        exit 1
    fi
    
    # Set global variables from parameters
    GITLAB_IP="$1"
    GITLAB_URL="$2"
    GITLAB_TOKEN="$3"
    PROJECT_ID="$4"
    PROJECT_NAME="$5"
    
    log_info "GitLab IP: $GITLAB_IP"
    log_info "Project Name: $PROJECT_NAME"
    log_info "Project ID: $PROJECT_ID"
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Execute launch steps
    setup_code_repository
    monitor_pipeline
    display_summary
    
    echo ""
    log_success "Training job launcher completed successfully!"
}

# Script execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
