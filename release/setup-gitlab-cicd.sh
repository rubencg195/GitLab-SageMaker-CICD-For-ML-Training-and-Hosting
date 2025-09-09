#!/bin/bash

# GitLab CI/CD Setup Script
# This script helps configure GitLab CI/CD variables and settings

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get GitLab CI/CD variables from OpenTofu outputs
get_tofu_outputs() {
    print_status "Getting OpenTofu outputs..."
    
    if ! command_exists tofu; then
        print_error "OpenTofu is not installed. Please install it first."
        exit 1
    fi
    
    # Get S3 bucket names
    ARTIFACTS_BUCKET=$(tofu output -raw gitlab_artifacts_bucket_name 2>/dev/null || echo "")
    RELEASES_BUCKET=$(tofu output -raw gitlab_releases_bucket_name 2>/dev/null || echo "")
    AWS_REGION=$(tofu output -raw aws_region 2>/dev/null || echo "us-east-1")
    
    if [ -z "$ARTIFACTS_BUCKET" ] || [ -z "$RELEASES_BUCKET" ]; then
        print_error "Could not get S3 bucket names from OpenTofu outputs."
        print_error "Make sure you have run 'tofu apply' successfully."
        exit 1
    fi
    
    print_success "Retrieved OpenTofu outputs:"
    echo "  Artifacts Bucket: $ARTIFACTS_BUCKET"
    echo "  Releases Bucket: $RELEASES_BUCKET"
    echo "  AWS Region: $AWS_REGION"
}

# Function to display GitLab CI/CD variable configuration
display_gitlab_variables() {
    print_status "GitLab CI/CD Variables Configuration"
    echo ""
    echo "You need to configure the following variables in your GitLab project:"
    echo ""
    echo "1. Go to your GitLab project: Settings > CI/CD > Variables"
    echo "2. Add the following variables:"
    echo ""
    echo "┌─────────────────────────────────┬─────────────────────────────────────────────────┐"
    echo "│ Variable Name                   │ Value                                           │"
    echo "├─────────────────────────────────┼─────────────────────────────────────────────────┤"
    echo "│ GITLAB_ARTIFACTS_BUCKET_NAME    │ $ARTIFACTS_BUCKET"
    echo "│ GITLAB_RELEASES_BUCKET_NAME     │ $RELEASES_BUCKET"
    echo "│ AWS_REGION                      │ $AWS_REGION"
    echo "│ PROJECT_NAME                    │ gitlab-server (or your project name)           │"
    echo "│ PROJECT_TYPE                    │ terraform (or python, nodejs, java, etc.)      │"
    echo "└─────────────────────────────────┴─────────────────────────────────────────────────┘"
    echo ""
    echo "3. For AWS credentials, you have two options:"
    echo ""
    echo "   Option A: Use IAM Role (Recommended for EC2 instances)"
    echo "   - Set AWS_ACCESS_KEY_ID to empty"
    echo "   - Set AWS_SECRET_ACCESS_KEY to empty"
    echo "   - The GitLab runner will use the EC2 instance's IAM role"
    echo ""
    echo "   Option B: Use Access Keys"
    echo "   - Set AWS_ACCESS_KEY_ID to your AWS access key"
    echo "   - Set AWS_SECRET_ACCESS_KEY to your AWS secret key (mark as masked)"
    echo ""
    echo "4. Mark the following variables as 'Protected' and 'Masked':"
    echo "   - AWS_SECRET_ACCESS_KEY (if using access keys)"
    echo ""
    echo "5. Mark the following variables as 'Protected' (but not masked):"
    echo "   - GITLAB_ARTIFACTS_BUCKET_NAME"
    echo "   - GITLAB_RELEASES_BUCKET_NAME"
    echo "   - AWS_REGION"
    echo "   - PROJECT_NAME"
    echo "   - PROJECT_TYPE"
}

# Function to create a sample .env file for local testing
create_env_file() {
    print_status "Creating sample .env file for local testing..."
    
    cat > .env.sample << EOF
# GitLab CI/CD Environment Variables
# Copy this file to .env and fill in your values

# S3 Configuration
GITLAB_ARTIFACTS_BUCKET_NAME=$ARTIFACTS_BUCKET
GITLAB_RELEASES_BUCKET_NAME=$RELEASES_BUCKET
AWS_REGION=$AWS_REGION

# Project Configuration
PROJECT_NAME=gitlab-server
PROJECT_TYPE=terraform

# AWS Credentials (if not using IAM role)
# AWS_ACCESS_KEY_ID=your_access_key_here
# AWS_SECRET_ACCESS_KEY=your_secret_key_here
EOF
    
    print_success "Created .env.sample file"
    print_warning "Do not commit .env file to version control!"
}

# Function to test S3 access
test_s3_access() {
    print_status "Testing S3 access..."
    
    if ! command_exists aws; then
        print_warning "AWS CLI not found. Install it to test S3 access."
        return
    fi
    
    # Test artifacts bucket access
    if aws s3 ls "s3://$ARTIFACTS_BUCKET" >/dev/null 2>&1; then
        print_success "Artifacts bucket access: OK"
    else
        print_error "Artifacts bucket access: FAILED"
    fi
    
    # Test releases bucket access
    if aws s3 ls "s3://$RELEASES_BUCKET" >/dev/null 2>&1; then
        print_success "Releases bucket access: OK"
    else
        print_error "Releases bucket access: FAILED"
    fi
}

# Function to display pipeline information
display_pipeline_info() {
    print_status "GitLab CI/CD Pipeline Information"
    echo ""
    echo "Your GitLab CI/CD pipeline will:"
    echo ""
    echo "1. 📦 Prepare: Set up build environment"
    echo "2. 🔨 Build: Build your project (customizable based on PROJECT_TYPE)"
    echo "3. 📦 Package: Create zip artifacts with metadata"
    echo "4. 🚀 Deploy: Upload artifacts to S3 buckets"
    echo "5. 🧹 Cleanup: Clean up temporary files"
    echo ""
    echo "Pipeline triggers:"
    echo "  - Push to any branch"
    echo "  - Merge request events"
    echo "  - Manual pipeline runs"
    echo ""
    echo "Artifacts created:"
    echo "  - {project}_{branch}_{commit}_{timestamp}.zip (full project)"
    echo "  - {project}_{branch}_{commit}_{timestamp}_source.zip (source code only)"
    echo "  - {project}_{branch}_{commit}_{timestamp}_docs.zip (documentation)"
    echo "  - {project}_{branch}_{commit}_{timestamp}_metadata.json (build metadata)"
    echo ""
    echo "S3 Storage structure:"
    echo "  - Artifacts: s3://$ARTIFACTS_BUCKET/artifacts/{branch}/"
    echo "  - Releases: s3://$RELEASES_BUCKET/releases/{tag}/"
}

# Function to create a test script
create_test_script() {
    print_status "Creating test script..."
    
    cat > test-pipeline.sh << 'EOF'
#!/bin/bash

# Test script for GitLab CI/CD pipeline
# This script simulates the pipeline locally

set -e

echo "🧪 Testing GitLab CI/CD pipeline locally..."

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "❌ .env file not found. Please create it from .env.sample"
    exit 1
fi

# Test variables
echo "📋 Testing variables..."
echo "Artifacts Bucket: ${GITLAB_ARTIFACTS_BUCKET_NAME:-NOT_SET}"
echo "Releases Bucket: ${GITLAB_RELEASES_BUCKET_NAME:-NOT_SET}"
echo "AWS Region: ${AWS_REGION:-NOT_SET}"
echo "Project Name: ${PROJECT_NAME:-NOT_SET}"
echo "Project Type: ${PROJECT_TYPE:-NOT_SET}"

# Test AWS access
echo "🔐 Testing AWS access..."
if aws sts get-caller-identity >/dev/null 2>&1; then
    echo "✅ AWS credentials working"
    aws sts get-caller-identity
else
    echo "❌ AWS credentials not working"
    exit 1
fi

# Test S3 access
echo "🪣 Testing S3 access..."
if aws s3 ls "s3://${GITLAB_ARTIFACTS_BUCKET_NAME}" >/dev/null 2>&1; then
    echo "✅ Artifacts bucket accessible"
else
    echo "❌ Artifacts bucket not accessible"
fi

if aws s3 ls "s3://${GITLAB_RELEASES_BUCKET_NAME}" >/dev/null 2>&1; then
    echo "✅ Releases bucket accessible"
else
    echo "❌ Releases bucket not accessible"
fi

echo "🎉 Test completed successfully!"
EOF
    
    chmod +x test-pipeline.sh
    print_success "Created test-pipeline.sh script"
}

# Main function
main() {
    echo "🚀 GitLab CI/CD Setup Script"
    echo "=============================="
    echo ""
    
    # Check prerequisites
    if ! command_exists tofu; then
        print_error "OpenTofu is required but not installed."
        print_error "Please install OpenTofu first: https://opentofu.org/docs/intro/install/"
        exit 1
    fi
    
    # Get OpenTofu outputs
    get_tofu_outputs
    
    # Display configuration instructions
    display_gitlab_variables
    
    # Create sample files
    create_env_file
    create_test_script
    
    # Test S3 access
    test_s3_access
    
    # Display pipeline information
    display_pipeline_info
    
    echo ""
    print_success "Setup completed!"
    echo ""
    echo "Next steps:"
    echo "1. Configure GitLab CI/CD variables as shown above"
    echo "2. Copy .env.sample to .env and fill in your values"
    echo "3. Run ./test-pipeline.sh to test locally"
    echo "4. Push your code to trigger the pipeline"
    echo ""
    echo "For more information, see the README.md file."
}

# Run main function
main "$@"
