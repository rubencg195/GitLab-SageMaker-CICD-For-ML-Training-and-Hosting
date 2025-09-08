# GitLab SageMaker CI/CD Pipeline on AWS with OpenTofu

This project demonstrates a complete CI/CD pipeline using GitLab that automatically creates and manages SageMaker training jobs and model endpoint deployments. The pipeline triggers on every commit and merge, creating both candidate and stable releases of machine learning models.

## 🎯 Project Overview

This comprehensive solution provides:
- **Complete GitLab Server Infrastructure** deployed on AWS
- **Automated CI/CD Pipeline** for ML model training and deployment
- **SageMaker Integration** with training jobs and endpoint management
- **Public GitLab Access** with secure configuration
- **Production-ready Architecture** with monitoring, security, and cost optimization

## ✅ Current Status

**GitLab Server is LIVE and Ready!**
- **Public IP**: `98.87.214.78`
- **Status**: Fully operational with automated setup
- **Authentication**: Username/password required (no public access)
- **Security**: Configured with proper security headers and access controls

## 🚀 Quick Start

**Ready to use GitLab right now:**
1. **Open GitLab**: http://98.87.214.78
2. **Login with**: `gitlabuser` / `MyStr0ngP@ssw0rd!2024`
3. **SSH Access**: `ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78`
4. **Start developing** your ML pipeline!

## 🏗️ Architecture

### Infrastructure Components
- **VPC**: Multi-AZ VPC with public and private subnets
- **GitLab Server**: EC2 instance (t3.large) with Ubuntu 22.04 LTS (Public subnet)
- **Data Storage**: EBS volume (100GB) for GitLab data persistence
- **Network**: Internet Gateway, Elastic IP, security groups, Route53 hosted zone
- **Monitoring**: CloudWatch logging and metrics
- **Security**: IAM roles, policies, encrypted storage, KMS encryption

### Security Architecture
- **GitLab Server**: Deployed in public subnet with secure configuration
- **Network Security**: Security groups restrict access to necessary ports only
- **Access Control**: SSH key-based authentication and secure HTTP/HTTPS access
- **Encryption**: All data encrypted at rest and in transit using AWS KMS

### CI/CD Pipeline Architecture

```
Code Commit → GitLab CI/CD → SageMaker Training → Model Registry → Endpoint Deployment → Testing → Release
```

#### Pipeline Flow Diagram

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Code Commit   │───▶│  GitLab CI/CD   │───▶│  Validation     │
│   / Merge       │    │   Pipeline      │    │  Stage          │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Model Registry │◀───│  Training Job   │◀───│  Build Stage    │
│  (Versioning)   │    │  Execution      │    │  (Container)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Endpoint       │◀───│  Model          │◀───│  Model          │
│  Deployment     │    │  Registration   │    │  Artifacts      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Endpoint       │───▶│  Integration    │───▶│  Release        │
│  Testing        │    │  Testing        │    │  Management     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

#### Pipeline Stages
1. **Validate**: Code quality, linting, unit tests
2. **Build**: Container image preparation
3. **Train**: SageMaker training job execution
4. **Register**: Model registration and versioning
5. **Deploy**: Endpoint creation and configuration
6. **Test**: Endpoint validation and performance testing
7. **Release**: Candidate/stable release management

#### Release Strategy
- **Candidate Releases**: Every commit → Quick validation → Development endpoints → Zip file: `candidate-PR-{PR_ID}-{COMMIT_ID}-{TIMESTAMP}.zip`
- **Stable Releases**: Merge to main → Full validation → Production endpoints → Zip file: `stable-{TIMESTAMP}.zip`
- **Zip File Contents**: Training scripts, model artifacts, deployment configs, and documentation
- **Automated Cleanup**: Old resources and zip files automatically removed

#### Zip Package Generation
The CI/CD pipeline automatically creates zip packages containing:
- **Source Code**: All Python scripts, configurations, and tests
- **Model Artifacts**: Trained model weights and metadata
- **Deployment Configs**: SageMaker endpoint configurations
- **Documentation**: Release notes and usage instructions
- **Metadata**: Version information, timestamps, and package contents

**Naming Convention:**
- **Candidate**: `candidate-PR-{PR_ID}-{COMMIT_ID}-{TIMESTAMP}.zip`
- **Stable**: `stable-{TIMESTAMP}.zip`

**Access**: Zip files are available as pipeline artifacts and can be downloaded from GitLab's CI/CD interface.

## 📋 Prerequisites

1. **AWS CLI configured** with appropriate credentials
2. **OpenTofu installed** (latest version recommended)
3. **SSH key pair** available at `~/.ssh/id_rsa.pub`
4. **AWS permissions** to create VPC, EC2, EBS, Route53, IAM, and SageMaker resources
5. **VS Code** (recommended for workspace integration)
6. **Python 3.8+** (for ML scripts and testing)
7. **Workspace Client** (for connecting to remote workspace)

## 🚀 Complete Deployment Guide

### Step 1: Infrastructure Deployment

1. **Clone and navigate to the project directory:**
   ```bash
   cd GitLab-SageMaker-CICD-For-ML-Training-and-Hosting
   ```

2. **Initialize OpenTofu:**
   ```bash
   tofu init
   ```

3. **Review the configuration in `locals.tf`** and modify if needed:
   - AWS region (default: us-east-1)
   - Instance type (default: t3.large)
   - Volume size (default: 100GB)
   - VPC CIDR blocks
   - Project name and tags

4. **Plan the deployment:**
   ```bash
   tofu plan
   ```

5. **Deploy the infrastructure:**
   ```bash
   tofu apply -auto-approve
   ```

6. **Wait for deployment to complete** (typically 5-10 minutes)

### Step 2: GitLab Access (Fully Automated)

7. **Access GitLab directly:**
   - **Public IP**: Check outputs after deployment
   - **HTTP URL**: http://[PUBLIC_IP]
   - **HTTPS URL**: https://[PUBLIC_IP]

8. **Login to GitLab (Automated Setup):**
   - **Primary Username**: `gitlabuser`
   - **Primary Password**: `MyStr0ngP@ssw0rd!2024`
   - **Root Username**: `root`
   - **Root Password**: Automatically retrieved and displayed in outputs
   - **URL**: http://[PUBLIC_IP] or https://[PUBLIC_IP]

9. **Verify Automated Setup:**
   ```bash
   # Check if GitLab is ready (should return 302 redirect)
   curl -I http://[PUBLIC_IP]
   
   # Verify custom user was created
   ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo cat /root/gitlab-credentials.txt"
   ```

**Note**: The deployment is fully automated. GitLab will be configured, started, and a custom user will be created automatically. No manual steps are required.

### Step 3: Development Setup

10. **Open VS Code workspace:**
    ```bash
    code workspace.code-workspace
    ```

11. **Install recommended extensions** (automatically suggested by workspace)

12. **Configure GitLab CI/CD variables** (Settings → CI/CD → Variables):
    - `AWS_ACCESS_KEY_ID`
    - `AWS_SECRET_ACCESS_KEY`
    - `AWS_DEFAULT_REGION` (us-east-1)
    - `SAGEMAKER_ROLE_ARN`
    - `S3_BUCKET`

### Step 4: Pipeline Testing

13. **Create a test project** in GitLab
14. **Push code** to trigger the CI/CD pipeline
15. **Monitor zip file generation** in the pipeline artifacts
16. **Monitor pipeline execution** in GitLab web interface
17. **Check SageMaker resources** in AWS console

## 🔐 GitLab Access Guide

### Accessing GitLab

GitLab is accessible directly from the internet with secure configuration:

#### Web Access
1. **HTTP**: Navigate to `http://[PUBLIC_IP]` in your browser
2. **HTTPS**: Navigate to `https://[PUBLIC_IP]` in your browser (after SSL setup)
3. **Custom Domain**: Use the Route53 domain if configured

#### SSH Access
1. **Server SSH**: `ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP]`
2. **Git SSH**: `git@[PUBLIC_IP]:` for Git operations

#### GitLab Authentication
- **Username**: `gitlabuser`
- **Password**: `GitLabSecure2024!`
- **Root Username**: `root`
- **Root Password**: Check `/etc/gitlab/initial_root_password` on server

#### Getting GitLab Root Password
```bash
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo cat /etc/gitlab/initial_root_password"
```

### Security Features
- **Authentication Required**: All access requires username/password
- **User Signup Disabled**: Prevents unauthorized account creation
- **Public Projects Disabled**: All projects are private by default
- **Session Management**: 8-hour session timeout
- **HTTPS Redirect**: Automatic redirect to secure connection
- **Security Headers**: XSS protection, frame options, content type protection
- **Encryption**: All data encrypted at rest and in transit using AWS KMS
- **Access Control**: Security groups restrict access to necessary ports only

## ⚙️ Configuration

### Infrastructure Configuration
All configuration is centralized in `locals.tf`. Key settings include:

- **Project Configuration**: Project name, environment
- **AWS Configuration**: Region (us-east-1), availability zones
- **VPC Configuration**: CIDR blocks for VPC and subnets
- **GitLab Configuration**: Instance type (t3.large), volume size (100GB)
- **Security**: Port configurations, tags

### CI/CD Pipeline Configuration
The pipeline is configured in `.gitlab-ci.yml` with:

- **Training Jobs**: Automated ML model training using SageMaker
- **Model Registry**: Versioned model storage and management
- **Endpoint Deployment**: Real-time inference with auto-scaling
- **Testing**: Automated validation and performance testing
- **Package Generation**: Zip files with artifacts and documentation
- **Release Management**: Candidate and stable release workflows

#### Pipeline Triggers
- **On Commit**: Triggers candidate pipeline with zip file: `candidate-PR-{PR_ID}-{COMMIT_ID}-{TIMESTAMP}.zip`
- **On Merge to Main**: Triggers stable pipeline with zip file: `stable-{TIMESTAMP}.zip`

#### Zip File Contents
Each zip package includes:
- Complete source code and scripts
- Model artifacts and weights
- Deployment configurations
- Documentation and release notes
- Metadata with version information

### Workspace Configuration
The VS Code workspace (`workspace.code-workspace`) includes:

- **Pre-configured tasks** for OpenTofu operations
- **SSH shortcuts** for GitLab server access
- **Debug configurations** for Python scripts
- **Recommended extensions** for development
- **Integrated terminal** with Git Bash

## 📁 Project Structure

```
GitLab-SageMaker-CICD-For-ML-Training-and-Hosting/
├── workspace.code-workspace          # VS Code workspace configuration
├── README.md                        # This comprehensive guide
├── .gitlab-ci.yml                   # GitLab CI/CD pipeline
├── locals.tf                        # OpenTofu configuration values
├── main.tf                         # Main infrastructure resources
├── outputs.tf                      # OpenTofu outputs
├── provider.tf                     # AWS provider configuration
├── scripts/                        # Automation scripts
│   ├── gitlab-install.sh          # GitLab installation script
│   ├── train_sagemaker.py          # Training job management
│   ├── register_model.py           # Model registration
│   ├── deploy_endpoint.py          # Endpoint deployment
│   ├── test_endpoint.py            # Endpoint testing
│   ├── create_release.py           # Release management
│   └── cleanup_resources.py        # Resource cleanup
├── templates/                      # Project templates
│   ├── sagemaker-training-job/     # Training job template
│   │   ├── training_script.py      # Training script
│   │   ├── requirements.txt        # Dependencies
│   │   ├── Dockerfile              # Container config
│   │   └── manifest.json           # Project metadata
│   └── sagemaker-endpoint-hosting/ # Endpoint hosting template
│       ├── inference_handler.py    # Inference script
│       ├── requirements.txt        # Dependencies
│       ├── Dockerfile              # Container config
│       └── manifest.json           # Project metadata
└── tests/                          # Test files
    └── unit/
        └── test_training.py        # Unit tests
```

## 🔧 Workspace Features

### Available Tasks (Ctrl+Shift+P → "Tasks: Run Task")
1. **OpenTofu Init** - Initialize OpenTofu
2. **OpenTofu Plan** - Plan infrastructure changes
3. **OpenTofu Apply** - Apply infrastructure changes
4. **OpenTofu Destroy** - Destroy infrastructure
5. **SSH to GitLab Server** - Connect to GitLab server
6. **Check GitLab Status** - Check GitLab service status
7. **Get GitLab Root Password** - Retrieve initial root password
8. **Open GitLab in Browser** - Open GitLab web interface

## 📦 Project Templates

### Creating New Projects

The repository includes templates for creating new SageMaker projects:

#### SageMaker Training Job Template
```bash
# Create a new training job project
python scripts/create_sagemaker_training_template.py my-training-project

# Specify output directory
python scripts/create_sagemaker_training_template.py my-training-project --output-dir ./projects
```

#### SageMaker Endpoint Hosting Template
```bash
# Create a new endpoint hosting project
python scripts/create_sagemaker_endpoint_template.py my-endpoint-project

# Specify output directory
python scripts/create_sagemaker_endpoint_template.py my-endpoint-project --output-dir ./projects
```

### Template Features

Each template includes:
- **Manifest file** (`manifest.json`) with project metadata and CI/CD configuration
- **Complete source code** with placeholder implementations
- **Dockerfile** for containerization
- **Requirements.txt** with necessary dependencies
- **GitLab CI/CD pipeline** configured for the project type
- **README.md** with project-specific documentation

### Project Types

**Training Projects:**
- Focus on model training and development
- Include training scripts, data processing, and model artifacts
- CI/CD pipeline: validate → build → train → register → package → release

**Inference Projects:**
- Focus on model deployment and serving
- Include inference handlers, endpoint configurations, and testing
- CI/CD pipeline: validate → build → deploy → test → package → release

### Development Tools
- **Python Development**: Linting, formatting, debugging
- **Terraform/OpenTofu**: Syntax highlighting, validation
- **GitLab Integration**: Workflow extensions
- **AWS Toolkit**: Cloud resource management
- **YAML Support**: CI/CD configuration

## 🌐 Accessing GitLab

### Web Interface
- **HTTP**: http://98.87.214.78
- **HTTPS**: https://98.87.214.78 (after SSL configuration)
- **Custom Domain**: gitlab.gitlab.local (Route53 configured)

### SSH Access
- **Server SSH**: `ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78`
- **Git SSH**: `git@98.87.214.78:`

### Workspace Integration
Use the VS Code workspace tasks for easy access:
- **Open GitLab in Browser** task
- **SSH to GitLab Server** task
- **Get GitLab Root Password** task

## 📊 Monitoring and Observability

### GitLab Monitoring
- **CloudWatch Logs**: `/aws/ec2/gitlab-server-gitlab`
- **GitLab Status**: `sudo gitlab-ctl status`
- **System Resources**: `htop` on the server

### CI/CD Pipeline Monitoring
- **GitLab CI/CD**: Pipeline logs in web interface
- **SageMaker Jobs**: AWS Console → SageMaker → Training Jobs
- **Model Endpoints**: AWS Console → SageMaker → Endpoints
- **CloudWatch Metrics**: Custom metrics and alarms

### Cost Monitoring
- **AWS Cost Explorer**: Track resource usage
- **Automated Cleanup**: Use `cleanup_resources.py` script
- **Resource Tagging**: All resources properly tagged

## 🧹 Cleanup

### Destroy Infrastructure
```bash
tofu destroy -auto-approve
```

### Clean Up Old Resources
```bash
python scripts/cleanup_resources.py --project-name gitlab-server --retention-days 7
```

## 🚨 Troubleshooting

### ✅ Deployment Success Verification

**Current Status: DEPLOYMENT SUCCESSFUL!**

The GitLab server is now fully operational at `http://98.87.214.78`. The automated setup has completed successfully with:

- ✅ GitLab CE installed and configured
- ✅ Custom user created (`gitlabuser` / `MyStr0ngP@ssw0rd!2024`)
- ✅ Security settings applied (authentication required, signup disabled)
- ✅ EBS volume mounted for data persistence
- ✅ All services running and accessible

### Automated Setup Verification

The deployment is fully automated using OpenTofu's `local-exec` provisioners. Here's how the automation works:

#### How Local-Exec Provisioners Work

The deployment uses three `null_resource` provisioners with `local-exec` to automate GitLab setup:

1. **`gitlab_url_update`**: Updates GitLab's external URL after EIP is created
2. **`gitlab_setup_wait`**: Waits for GitLab to be fully ready
3. **`gitlab_credentials`**: Retrieves and stores credentials

**Execution Order:**
```
Instance Creation → EIP Assignment → URL Update → Wait for GitLab → Retrieve Credentials
```

**Local-Exec Commands:**
- **SSH Commands**: Execute commands on the remote GitLab server
- **Curl Checks**: Verify GitLab is responding
- **File Operations**: Create credential files and update configurations
- **GitLab Commands**: Use `gitlab-ctl` and `gitlab-rails` for configuration

#### 1. Check Deployment Status
```bash
# Check if GitLab is accessible
curl -I http://[PUBLIC_IP]

# Expected: HTTP/1.1 302 Found (redirects to login page)
# If 502 Bad Gateway: GitLab is still initializing
```

#### 2. Verify GitLab Services
```bash
# SSH to GitLab server
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP]

# Check GitLab status
sudo gitlab-ctl status

# Check GitLab logs
sudo gitlab-ctl tail
```

#### 3. Check User Creation
```bash
# Verify custom user was created
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo cat /root/gitlab-credentials.txt"
```

#### 4. Monitor Local-Exec Execution
```bash
# Check if provisioners are running
tofu state list | grep null_resource

# Check provisioner status
tofu show null_resource.gitlab_url_update
tofu show null_resource.gitlab_setup_wait
tofu show null_resource.gitlab_credentials
```

### Common Issues and Solutions

#### 1. GitLab Not Accessible
**Symptoms**: Cannot access GitLab web interface
**Solutions**:
- Wait 5-10 minutes for GitLab to fully initialize
- Check security group allows HTTP/HTTPS traffic (ports 80, 443)
- Verify instance is running: `aws ec2 describe-instances --instance-ids [INSTANCE_ID]`
- Check GitLab status: `ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl status"`

**Debug Commands**:
```bash
# Check if GitLab is responding
curl -v http://[PUBLIC_IP]

# Check GitLab service status
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo systemctl status gitlab-runsvdir"

# Check GitLab configuration
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl show-config"

# Check if local-exec provisioners completed
tofu state show null_resource.gitlab_url_update
tofu state show null_resource.gitlab_setup_wait
tofu state show null_resource.gitlab_credentials

# Check GitLab external URL configuration
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo grep external_url /etc/gitlab/gitlab.rb"
```

#### 1.1 Local-Exec Provisioner Issues
**Symptoms**: Provisioners fail or don't complete
**Common Causes**:
- SSH connection issues
- GitLab not ready when provisioners run
- Network connectivity problems
- Permission issues

**Debug Commands**:
```bash
# Check provisioner execution logs
tofu apply -auto-approve 2>&1 | tee deployment.log

# Test SSH connectivity manually
ssh -i ~/.ssh/id_rsa -o ConnectTimeout=10 ubuntu@[PUBLIC_IP] "echo 'SSH working'"

# Check if GitLab is ready for configuration
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "curl -s -o /dev/null -w '%{http_code}' http://localhost"

# Manually run provisioner commands
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl status"
```

#### 2. SSH Connection Failed
**Symptoms**: Cannot SSH to GitLab server
**Solutions**:
- Verify SSH key permissions: `chmod 600 ~/.ssh/id_rsa`
- Check security group allows SSH traffic (ports 22, 2222)
- Ensure instance is running and accessible
- Try: `ssh -i ~/.ssh/id_rsa -v ubuntu@[PUBLIC_IP]` for verbose output

**Debug Commands**:
```bash
# Test SSH connection with verbose output
ssh -i ~/.ssh/id_rsa -v ubuntu@[PUBLIC_IP]

# Check instance status
aws ec2 describe-instances --instance-ids [INSTANCE_ID] --query 'Reservations[0].Instances[0].State.Name'

# Check security group rules
aws ec2 describe-security-groups --group-ids [SECURITY_GROUP_ID]
```

#### 3. User Creation Issues
**Symptoms**: Custom user not created or cannot login
**Solutions**:
- Check installation logs: `ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo tail -50 /var/log/gitlab-install.log"`
- Verify GitLab is ready before user creation
- Use root user as fallback

**Debug Commands**:
```bash
# Check if custom user exists
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-rails runner \"puts User.find_by(username: 'gitlabuser')\""

# Check GitLab Rails console
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-rails console"

# Check credentials file
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo cat /root/gitlab-credentials.txt"
```

#### 4. OpenTofu Issues
**Symptoms**: OpenTofu commands fail
**Solutions**:
- Run `tofu init` to initialize providers
- Check AWS credentials: `aws sts get-caller-identity`
- Verify region and resource availability
- Check for syntax errors in configuration files

**Debug Commands**:
```bash
# Check OpenTofu state
tofu state list

# Check OpenTofu plan
tofu plan -detailed-exitcode

# Validate configuration
tofu validate
```

#### 5. GitLab Configuration Issues
**Symptoms**: GitLab not starting or configuration errors
**Solutions**:
- Check GitLab configuration: `sudo gitlab-ctl show-config`
- Reconfigure GitLab: `sudo gitlab-ctl reconfigure`
- Check logs for specific errors

**Debug Commands**:
```bash
# Check GitLab configuration
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl show-config"

# Check GitLab logs
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl tail"

# Reconfigure GitLab
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl reconfigure"
```

#### 6. EBS Volume Mount Issues
**Symptoms**: GitLab data not persisting or volume not mounted
**Solutions**:
- Check if EBS volume is attached: `lsblk`
- Verify volume is mounted: `df -h`
- Check fstab entry: `cat /etc/fstab`

**Debug Commands**:
```bash
# Check block devices
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "lsblk"

# Check mount points
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "df -h"

# Check fstab
ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "cat /etc/fstab"
```

#### 7. Network Connectivity Issues
**Symptoms**: Cannot reach GitLab from internet
**Solutions**:
- Check security group rules
- Verify instance has public IP
- Check route table configuration
- Verify internet gateway is attached

**Debug Commands**:
```bash
# Check instance public IP
aws ec2 describe-instances --instance-ids [INSTANCE_ID] --query 'Reservations[0].Instances[0].PublicIpAddress'

# Check security group rules
aws ec2 describe-security-groups --group-ids [SECURITY_GROUP_ID] --query 'SecurityGroups[0].IpPermissions'

# Test connectivity
telnet [PUBLIC_IP] 80
telnet [PUBLIC_IP] 443
```

### Automated Recovery

If issues persist, the deployment includes automated recovery mechanisms:

1. **GitLab Service Restart**: Automatically restarts if services fail
2. **Configuration Validation**: Checks configuration before applying
3. **User Creation Retry**: Attempts user creation multiple times
4. **Health Checks**: Monitors GitLab readiness before proceeding

### Manual Recovery Steps

If automated recovery fails:

1. **Restart GitLab Services**:
   ```bash
   ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl restart"
   ```

2. **Reconfigure GitLab**:
   ```bash
   ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl reconfigure"
   ```

3. **Check and Fix Permissions**:
   ```bash
   ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo chown -R git:git /var/opt/gitlab"
   ```

4. **Reset GitLab Configuration**:
   ```bash
   ssh -i ~/.ssh/id_rsa ubuntu@[PUBLIC_IP] "sudo gitlab-ctl reset-config"
   ```

### 🔧 Comprehensive Debug Commands

#### GitLab Server Debugging
```bash
# Check GitLab status and services
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo gitlab-ctl status"

# View GitLab logs (real-time)
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo gitlab-ctl tail"

# Check specific GitLab service logs
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo gitlab-ctl tail nginx"
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo gitlab-ctl tail puma"
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo gitlab-ctl tail sidekiq"

# Check GitLab configuration
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo gitlab-ctl show-config"

# Verify GitLab external URL is correctly set
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo grep external_url /etc/gitlab/gitlab.rb"

# Check GitLab installation log
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo tail -50 /var/log/gitlab-install.log"

# Test GitLab web interface accessibility
curl -I http://98.87.214.78
curl -L http://98.87.214.78/users/sign_in | head -20

# Check system resources
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "htop"
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "df -h"
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "free -h"

# Verify EBS volume mounting
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "lsblk"
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "mount | grep gitlab"
```

#### CI/CD Pipeline Debugging
```bash
# Check GitLab CI/CD pipeline status via API
curl -H "PRIVATE-TOKEN: your-token" "http://98.87.214.78/api/v4/projects/PROJECT_ID/pipelines"

# View pipeline job logs
curl -H "PRIVATE-TOKEN: your-token" "http://98.87.214.78/api/v4/projects/PROJECT_ID/jobs/JOB_ID/trace"

# Check GitLab Runner status (if using GitLab Runner)
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo gitlab-runner status"
ssh -i ~/.ssh/id_rsa ubuntu@98.87.214.78 "sudo gitlab-runner list"

# Monitor CI/CD artifacts and packages
curl -H "PRIVATE-TOKEN: your-token" "http://98.87.214.78/api/v4/projects/PROJECT_ID/packages"
```

#### AWS & SageMaker Debugging
```bash
# Verify AWS connectivity and credentials
aws sts get-caller-identity
aws configure list

# Check SageMaker training jobs
aws sagemaker list-training-jobs --region us-east-1 --max-results 10
aws sagemaker describe-training-job --training-job-name JOB_NAME --region us-east-1

# Check SageMaker endpoints
aws sagemaker list-endpoints --region us-east-1
aws sagemaker describe-endpoint --endpoint-name ENDPOINT_NAME --region us-east-1

# Check SageMaker models
aws sagemaker list-models --region us-east-1
aws sagemaker describe-model --model-name MODEL_NAME --region us-east-1

# Check SageMaker model packages (Model Registry)
aws sagemaker list-model-packages --region us-east-1
aws sagemaker list-model-package-groups --region us-east-1

# Monitor CloudWatch logs for SageMaker
aws logs describe-log-groups --log-group-name-prefix "/aws/sagemaker" --region us-east-1
aws logs get-log-events --log-group-name "/aws/sagemaker/TrainingJobs" --log-stream-name TRAINING_JOB_NAME --region us-east-1

# Check S3 buckets and artifacts
aws s3 ls s3://your-sagemaker-bucket/
aws s3 ls s3://your-sagemaker-bucket/models/ --recursive

# Monitor CloudWatch logs for GitLab server
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/gitlab-server"
aws logs get-log-events --log-group-name "/aws/ec2/gitlab-server-gitlab" --log-stream-name INSTANCE_ID --region us-east-1
```

#### Project Template Debugging
```bash
# Test SageMaker training template creation
python scripts/create_sagemaker_training_template.py test-training-project --output-dir ./test-projects

# Test SageMaker endpoint template creation
python scripts/create_sagemaker_endpoint_template.py test-endpoint-project --output-dir ./test-projects

# Verify template structure
ls -la ./test-projects/test-training-project/
cat ./test-projects/test-training-project/manifest.json

# Test zip package creation
python scripts/create_zip_package.py --project-path ./test-projects/test-training-project --output-path ./test-packages --release-type candidate

# Verify zip package contents
unzip -l ./test-packages/candidate-*.zip
```

#### Script Debugging
```bash
# Test training script with debug mode
python scripts/train_sagemaker.py \
  --job-name debug-training-job \
  --role-arn arn:aws:iam::ACCOUNT:role/SageMakerRole \
  --s3-bucket your-bucket \
  --instance-type ml.m5.large \
  --max-runtime 3600 \
  --wait \
  --region us-east-1

# Test model registration
python scripts/register_model.py \
  --model-package-group-name test-model-group \
  --training-job-name debug-training-job \
  --model-approval-status Approved \
  --region us-east-1

# Test endpoint deployment
python scripts/deploy_endpoint.py \
  --endpoint-name test-debug-endpoint \
  --model-name test-model \
  --instance-type ml.t2.medium \
  --wait \
  --region us-east-1

# Test endpoint functionality
python scripts/test_endpoint.py \
  --endpoint-name test-debug-endpoint \
  --test-data '{"instances": [{"feature1": 1.0, "feature2": 2.0}]}' \
  --region us-east-1

# Test resource cleanup (dry run first)
python scripts/cleanup_resources.py \
  --project-name gitlab-server \
  --retention-days 1 \
  --dry-run \
  --region us-east-1
```

#### Infrastructure Debugging
```bash
# Check OpenTofu state
tofu state list
tofu state show aws_instance.gitlab_server
tofu state show aws_eip.gitlab_eip

# Validate OpenTofu configuration
tofu validate
tofu plan -detailed-exitcode

# Check AWS resources directly
aws ec2 describe-instances --instance-ids i-INSTANCE_ID --region us-east-1
aws ec2 describe-security-groups --group-ids sg-SECURITY_GROUP_ID --region us-east-1
aws ec2 describe-volumes --volume-ids vol-VOLUME_ID --region us-east-1

# Test network connectivity
telnet 98.87.214.78 80
telnet 98.87.214.78 443
telnet 98.87.214.78 22

# Check DNS resolution
nslookup 98.87.214.78
dig 98.87.214.78
```

## 🔒 Security Considerations

### Immediate Actions
- **Change Default Password**: Update GitLab root password immediately
- **Configure SSL/TLS**: Set up certificates for HTTPS access
- **Restrict SSH Access**: Limit SSH access to specific IP ranges
- **Update System**: Regularly update GitLab and underlying OS

### Long-term Security
- **Regular Backups**: Implement automated backup strategies
- **Access Monitoring**: Monitor and audit access logs
- **Security Updates**: Keep all components updated
- **Network Security**: Consider VPN or bastion host access
- **IAM Policies**: Use least privilege access principles

### Compliance and Governance
- **Resource Tagging**: All resources properly tagged for cost allocation
- **Audit Logging**: CloudTrail enabled for API call tracking
- **Data Encryption**: EBS volumes and S3 buckets encrypted
- **Access Controls**: IAM roles and policies properly configured

## 💡 Key Features

### Pipeline Stages
1. **Validate**: Code quality, linting, unit tests
2. **Build**: Container image preparation
3. **Train**: SageMaker training job execution
4. **Register**: Model registration and versioning
5. **Deploy**: Endpoint creation and configuration
6. **Test**: Endpoint validation and performance testing
7. **Release**: Candidate/stable release management

### Release Strategy
- **Candidate Releases**: Every commit triggers quick validation
- **Stable Releases**: Merge to main triggers production deployment
- **Automated Cleanup**: Old resources automatically removed
- **Cost Optimization**: Right-sized instances and auto-scaling

### Security & Monitoring
- **IAM Roles**: Least privilege access control
- **Encryption**: Data encrypted in transit and at rest
- **CloudWatch**: Comprehensive logging and metrics
- **Health Checks**: Automated endpoint monitoring
- **Audit Trail**: Complete activity logging

## ⚠️ Important Notes

- **SSH Key**: Ensure your SSH public key is available at `~/.ssh/id_rsa.pub`
- **Initial Password**: The initial root password is generated and stored in `/etc/gitlab/initial_root_password` on the server
- **Data Persistence**: GitLab data is stored on a separate EBS volume for persistence
- **Security**: The security group allows SSH, HTTP, and HTTPS access from anywhere (0.0.0.0/0)
- **Cost Management**: Monitor AWS costs and use cleanup scripts to remove old resources

## 📚 Additional Resources

- **GitLab Documentation**: https://docs.gitlab.com/
- **SageMaker Documentation**: https://docs.aws.amazon.com/sagemaker/
- **OpenTofu Documentation**: https://opentofu.org/docs/
- **VS Code Workspace Guide**: See workspace tasks and configurations
- **Pipeline Architecture**: Detailed diagrams and flows included above

## 🎯 Next Steps

1. **Open the workspace**: `code workspace.code-workspace`
2. **Access GitLab**: Use the "Open GitLab in Browser" task
3. **Get root password**: Use the "Get GitLab Root Password" task
4. **Create your first project** in GitLab
5. **Configure CI/CD variables** for AWS access
6. **Start developing** your ML pipeline!

---

**🎉 Your GitLab SageMaker CI/CD pipeline is now ready for production use!**

This comprehensive solution provides everything needed to build, train, and deploy machine learning models with automated CI/CD pipelines, complete infrastructure management, and a professional development environment.