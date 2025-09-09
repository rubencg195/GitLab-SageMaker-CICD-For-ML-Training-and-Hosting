# GitLab CI/CD Pipeline for Automatic Artifact Management

This directory contains the GitLab CI/CD pipeline configuration and setup scripts for automatically zipping and uploading project content to S3 when PRs are created, commits are pushed, or merges occur.

## 🎯 Overview

The CI/CD pipeline provides:
- **Automatic Artifact Creation**: Zips project content on every push, PR, or merge
- **S3 Storage**: Uploads artifacts to dedicated S3 buckets
- **Metadata Tracking**: Creates detailed build metadata for each artifact
- **Multi-format Support**: Supports different project types (Python, Node.js, Java, Terraform, etc.)
- **Release Management**: Special handling for tagged releases

## 📁 Files

- `.gitlab-ci.yml` - Main GitLab CI/CD pipeline configuration
- `setup-gitlab-cicd.sh` - Setup script for configuring GitLab variables
- `README.md` - This documentation file

## 🚀 Quick Start

### 1. Deploy Infrastructure

First, make sure your GitLab server and S3 buckets are deployed:

```bash
# Deploy the infrastructure
tofu apply -auto-approve

# Get S3 bucket information
tofu output gitlab_artifacts_bucket_name
tofu output gitlab_releases_bucket_name
```

### 2. Configure GitLab CI/CD Variables

Run the setup script to get the required variables:

```bash
cd release
./setup-gitlab-cicd.sh
```

This will display the GitLab CI/CD variables you need to configure in your GitLab project.

### 3. Set GitLab Variables

Go to your GitLab project: **Settings > CI/CD > Variables** and add:

| Variable Name | Value | Protected | Masked |
|---------------|-------|-----------|--------|
| `GITLAB_ARTIFACTS_BUCKET_NAME` | From OpenTofu output | ✅ | ❌ |
| `GITLAB_RELEASES_BUCKET_NAME` | From OpenTofu output | ✅ | ❌ |
| `AWS_REGION` | `us-east-1` | ✅ | ❌ |
| `PROJECT_NAME` | `gitlab-server` | ✅ | ❌ |
| `PROJECT_TYPE` | `terraform` | ❌ | ❌ |

### 4. Configure AWS Credentials

**Option A: IAM Role (Recommended)**
- Leave `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` empty
- The GitLab runner will use the EC2 instance's IAM role

**Option B: Access Keys**
- Set `AWS_ACCESS_KEY_ID` to your AWS access key
- Set `AWS_SECRET_ACCESS_KEY` to your AWS secret key (mark as masked)

### 5. Test the Pipeline

```bash
# Test locally
./test-pipeline.sh

# Or trigger a pipeline by pushing code
git add .
git commit -m "Add CI/CD pipeline"
git push
```

## 🔧 Pipeline Stages

### 1. Prepare
- Sets up build environment
- Installs dependencies
- Creates build directories

### 2. Build
- Builds the project based on `PROJECT_TYPE`
- Supports: Python, Node.js, Java, Terraform, Generic
- Collects project files

### 3. Package
- Creates multiple zip artifacts:
  - **Full project zip**: Complete project with all files
  - **Source code zip**: Only source code files
  - **Documentation zip**: Only documentation files
- Generates build metadata JSON

### 4. Deploy
- Uploads artifacts to S3 buckets
- Stores in organized folder structure
- Handles both regular commits and releases

### 5. Cleanup
- Cleans up temporary files
- Sends notifications

## 📦 Artifact Structure

### S3 Storage Layout

```
s3://gitlab-server-production-artifacts-xxxx/
├── artifacts/
│   ├── main/
│   │   ├── project_main_abc123_20250109_143022.zip
│   │   ├── project_main_abc123_20250109_143022_source.zip
│   │   ├── project_main_abc123_20250109_143022_docs.zip
│   │   └── project_main_abc123_20250109_143022_metadata.json
│   ├── feature-branch/
│   │   └── ...
│   └── develop/
│       └── ...
└── ...

s3://gitlab-server-production-releases-xxxx/
├── releases/
│   ├── v1.0.0/
│   │   ├── project_v1.0.0_20250109_143022.zip
│   │   ├── project_v1.0.0_20250109_143022_source.zip
│   │   ├── project_v1.0.0_20250109_143022_docs.zip
│   │   └── project_v1.0.0_20250109_143022_metadata.json
│   └── v1.1.0/
│       └── ...
└── ...
```

### Artifact Naming Convention

- **Regular commits**: `{project}_{branch}_{commit_short}_{timestamp}.zip`
- **Releases**: `{project}_{tag}_{timestamp}.zip`
- **Metadata**: `{project}_{branch}_{commit_short}_{timestamp}_metadata.json`

## 🔍 Metadata Structure

Each build creates a metadata JSON file with:

```json
{
  "project_name": "gitlab-server",
  "version": "v1.0.0",
  "branch": "main",
  "commit_sha": "abc123def456...",
  "commit_short": "abc123",
  "pipeline_id": "123456",
  "job_id": "789012",
  "build_timestamp": "20250109_143022",
  "build_date": "2025-01-09T14:30:22Z",
  "gitlab_url": "https://gitlab.com/user/project",
  "pipeline_url": "https://gitlab.com/user/project/-/pipelines/123456",
  "trigger_source": "push",
  "artifacts": [
    "project_main_abc123_20250109_143022.zip",
    "project_main_abc123_20250109_143022_source.zip",
    "project_main_abc123_20250109_143022_docs.zip"
  ]
}
```

## 🎛️ Configuration Options

### Project Types

Set `PROJECT_TYPE` variable to customize build behavior:

- **`python`**: Installs pip dependencies, compiles Python files
- **`nodejs`**: Runs npm install and build
- **`java`**: Runs Gradle or Maven build
- **`terraform`**: Validates Terraform configuration
- **`generic`**: Collects all files without specific build steps

### Custom Build Commands

You can customize the build stage by modifying the `.gitlab-ci.yml` file in the `build` job.

## 🔐 Security

- **IAM Roles**: Uses least-privilege IAM roles for S3 access
- **Encryption**: All S3 buckets use server-side encryption
- **Access Control**: Bucket policies restrict access to authorized roles only
- **Variable Protection**: Sensitive variables are marked as protected and masked

## 📊 Monitoring

### Pipeline Status
- View pipeline status in GitLab: **CI/CD > Pipelines**
- Check job logs for detailed information
- Monitor artifact uploads in S3

### S3 Monitoring
- Use AWS CloudWatch for S3 metrics
- Set up S3 access logging if needed
- Monitor bucket storage costs

## 🚨 Troubleshooting

### Common Issues

1. **Pipeline fails with "Access Denied"**
   - Check IAM role permissions
   - Verify S3 bucket names are correct
   - Ensure AWS credentials are properly configured

2. **Artifacts not uploading**
   - Check S3 bucket policies
   - Verify bucket names in GitLab variables
   - Check AWS region configuration

3. **Build stage fails**
   - Check PROJECT_TYPE variable
   - Verify build dependencies are available
   - Check build script syntax

### Debug Commands

```bash
# Test AWS access
aws sts get-caller-identity

# Test S3 access
aws s3 ls s3://your-bucket-name

# Check GitLab variables
echo $GITLAB_ARTIFACTS_BUCKET_NAME
echo $GITLAB_RELEASES_BUCKET_NAME

# Run local test
./test-pipeline.sh
```

## 🔄 Advanced Usage

### Custom Artifact Types

To add custom artifact types, modify the `package` stage in `.gitlab-ci.yml`:

```yaml
# Add custom zip creation
- echo "Creating custom artifact..."
- zip -r ${RELEASE_DIR}/${PACKAGE_NAME}_custom.zip ./custom-folder
```

### Conditional Builds

Add conditions to build stages:

```yaml
build:
  script:
    - |
      if [ "${CI_COMMIT_BRANCH}" == "main" ]; then
        echo "Building production version..."
        # Production build commands
      else
        echo "Building development version..."
        # Development build commands
      fi
```

### Notifications

Configure notifications in the `notify` stage:

```yaml
notify:
  script:
    - |
      # Send Slack notification
      curl -X POST -H 'Content-type: application/json' \
        --data '{"text":"Pipeline completed successfully!"}' \
        $SLACK_WEBHOOK_URL
```

## 📚 Additional Resources

- [GitLab CI/CD Documentation](https://docs.gitlab.com/ee/ci/)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [OpenTofu Documentation](https://opentofu.org/docs/)

## 🤝 Contributing

To contribute to this CI/CD pipeline:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the pipeline
5. Submit a pull request

## 📄 License

This project is part of the GitLab-SageMaker-CICD-For-ML-Training-and-Hosting project.
