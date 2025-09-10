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

# Function to setup training code repository
setup_code_repository() {
    log_info "Setting up training scripts repository..."
    
    # Create temporary directory for GitLab repository content
    TEMP_REPO_DIR="/tmp/gitlab-training-repo-$$"
    rm -rf "$TEMP_REPO_DIR"
    mkdir -p "$TEMP_REPO_DIR"
    
    log_info "Preparing training scripts repository structure..."
    
    # Copy only the training-related files to temp directory
    if [ -d "train-script" ]; then
        cp -r train-script/* "$TEMP_REPO_DIR/"
        log_success "Copied training scripts"
    else
        error_exit "train-script directory not found"
    fi
    
    # Copy CI/CD configuration
    if [ -f ".gitlab-ci.yml" ]; then
        cp .gitlab-ci.yml "$TEMP_REPO_DIR/"
        log_success "Copied CI/CD configuration"
    fi
    
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
    
    # Create a simple README for the training repository
    cat > "$TEMP_REPO_DIR/README.md" << 'EOF'
# SageMaker ML Training Pipeline Demo

This repository contains a simplified training pipeline demo for SageMaker ML model training.

## Structure

- `train.py` - Main training script
- `create_zip_package.py` - Package and upload artifacts
- `.gitlab-ci.yml` - CI/CD pipeline configuration

## Pipeline Stages

1. **validate** - Code quality checks
2. **train** - XGBoost model training
3. **package** - Artifact compression and S3 upload

## Artifacts

- Trained models are packaged as ZIP files
- Artifacts are stored in S3 buckets

Generated automatically by GitLab CI/CD launcher script.
EOF
    
    # Initialize git repository in temp directory
    cd "$TEMP_REPO_DIR"
    git init
    git config user.email "gitlab-cicd@localhost"
    git config user.name "GitLab CI/CD Setup"
    
    # Add all files
    git add .
    git commit -m "Initial commit: Training scripts and CI/CD pipeline"
    
    # Add GitLab remote and push
    git remote add origin "$GITLAB_URL/root/$PROJECT_NAME.git"
    
    # Configure git authentication with access token
    git remote set-url origin "http://root:$GITLAB_TOKEN@$GITLAB_IP/root/$PROJECT_NAME.git"
    
    if git push -u origin master --force; then
        log_success "Training scripts repository pushed to GitLab"
    else
        log_warning "Failed to push training scripts to GitLab"
    fi
    
    # Return to project root and cleanup
    cd "$PROJECT_ROOT"
    rm -rf "$TEMP_REPO_DIR"
    
    log_info "Repository setup complete - GitLab now contains training demo"
}

# Function to monitor pipeline
monitor_pipeline() {
    log_info "Monitoring GitLab CI/CD pipeline..."
    
    # Wait a moment for pipeline to start
    sleep 5
    
    # Get latest pipeline
    PIPELINE_INFO=$(curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines" | head -200)
    
    if echo "$PIPELINE_INFO" | grep -q '"status"'; then
        PIPELINE_STATUS=$(echo "$PIPELINE_INFO" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
        PIPELINE_ID=$(echo "$PIPELINE_INFO" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        PIPELINE_URL="$GITLAB_URL/root/$PROJECT_NAME/-/pipelines/$PIPELINE_ID"
        
        log_info "Latest pipeline status: $PIPELINE_STATUS"
        log_info "Pipeline URL: $PIPELINE_URL"
        
        if [ "$PIPELINE_STATUS" = "success" ]; then
            log_success "Pipeline completed successfully!"
        elif [ "$PIPELINE_STATUS" = "failed" ]; then
            log_warning "Pipeline failed. Check the GitLab UI for details."
        elif [ "$PIPELINE_STATUS" = "running" ] || [ "$PIPELINE_STATUS" = "pending" ]; then
            log_info "Pipeline is $PIPELINE_STATUS. Monitor at: $PIPELINE_URL"
        fi
    else
        log_warning "Could not get pipeline status"
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
    echo "  • Artifacts: $(tofu output -raw gitlab_artifacts_bucket_name 2>/dev/null || echo 'N/A')"
    echo "  • Releases: $(tofu output -raw gitlab_releases_bucket_name 2>/dev/null || echo 'N/A')"
    echo ""
    echo "Training Pipeline Features:"
    echo "  • ✅ Simplified training demo"
    echo "  • ✅ S3 artifact storage"
    echo "  • ✅ Automated packaging"
    echo ""
    echo "Next Steps:"
    echo "  1. Visit GitLab project: $GITLAB_URL/root/$PROJECT_NAME"
    echo "  2. Monitor pipeline: $GITLAB_URL/root/$PROJECT_NAME/-/pipelines"
    echo "  3. Check S3 buckets for training artifacts"
    echo ""
    echo -e "${BLUE}Training job launched! 🚀${NC}"
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
