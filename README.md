# GitLab SageMaker CI/CD Pipeline on AWS with OpenTofu

This project demonstrates a complete CI/CD pipeline using GitLab that automatically creates and manages SageMaker training jobs and model endpoint deployments. The pipeline triggers on every commit and merge, creating both candidate and stable releases of machine learning models.

## 🎯 Project Overview

This comprehensive solution provides:
- **Complete GitLab Server Infrastructure** deployed on AWS
- **Automated CI/CD Pipeline** for ML model training and deployment
- **SageMaker Integration** with training jobs and endpoint management
- **VS Code Workspace** with pre-configured development environment
- **Production-ready Architecture** with monitoring, security, and cost optimization

## 🏗️ Architecture

### Infrastructure Components
- **VPC**: Multi-AZ VPC with public and private subnets
- **Workspace Server**: Ubuntu desktop with VS Code Server, RDP, VNC access (Public subnet)
- **GitLab Server**: EC2 instance (t3.large) with Ubuntu 22.04 LTS (Private subnet)
- **Data Storage**: EBS volume (100GB) for GitLab data persistence
- **Network**: NAT Gateway, Elastic IP, security groups, Route53 hosted zone
- **Monitoring**: CloudWatch logging and metrics
- **Security**: IAM roles, policies, encrypted storage, and bastion host architecture

### Security Architecture
- **GitLab Server**: Isolated in private subnet, accessible only via workspace
- **Workspace Server**: Bastion host in public subnet with multiple access methods
- **Network Security**: Security groups restrict traffic between components
- **Access Control**: All GitLab access must go through the workspace server

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
   - AWS region (default: us-west-2)
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

### Step 1.5: Access Workspace via Amazon WorkSpaces Web Client

**Web Access (Recommended):**
1. Navigate to [Amazon WorkSpaces Web Client](https://clients.amazonworkspaces.com/)
2. Enter your workspace registration code (provided in outputs after deployment)
3. Login with your workspace credentials
4. Access your development environment directly in your browser

**Alternative Client Applications:**
- **Windows**: Download from [Amazon WorkSpaces Client](https://clients.amazonworkspaces.com/)
- **macOS**: Download from [Amazon WorkSpaces Client](https://clients.amazonworkspaces.com/)
- **Linux**: Install from [Amazon WorkSpaces Client](https://clients.amazonworkspaces.com/)
- **Mobile**: Available for Android and iOS from respective app stores

### Step 2: Workspace and GitLab Access

7. **Access Workspace Server:**
   - **Public IP**: 35.90.17.111 (check outputs for current IP)
   - **Username**: `ubuntu`
   - **Password**: `workspace123!`
   
   **Access Methods:**
   - **SSH**: `ssh -i ~/.ssh/id_rsa ubuntu@35.90.17.111`
   - **RDP**: `rdp://35.90.17.111:3389`
   - **VNC**: `vnc://35.90.17.111:5900`
   - **VS Code Server**: `http://35.90.17.111:8080`

8. **Access GitLab through Workspace:**
   - **URL**: http://10.0.10.25 (GitLab private IP)
   - **SSH to GitLab**: `ssh -i ~/.ssh/id_rsa ubuntu@35.90.17.111 'ssh ubuntu@10.0.10.25'`

9. **Get GitLab initial root password:**
   ```bash
   # From workspace server
   ssh ubuntu@10.0.10.25 "sudo cat /etc/gitlab/initial_root_password"
   ```

10. **Login to GitLab:**
    - Username: `root`
    - Password: Use the password from step 9
    - **Important**: Change the password immediately after first login

### Step 3: Workspace Setup

11. **Open VS Code workspace:**
    ```bash
    code workspace.code-workspace
    ```

12. **Install recommended extensions** (automatically suggested by workspace)

13. **Configure GitLab CI/CD variables** (Settings → CI/CD → Variables):
    - `AWS_ACCESS_KEY_ID`
    - `AWS_SECRET_ACCESS_KEY`
    - `AWS_DEFAULT_REGION` (us-west-2)
    - `SAGEMAKER_ROLE_ARN`
    - `S3_BUCKET`

### Step 4: Pipeline Testing

14. **Create a test project** in GitLab
15. **Push code** to trigger the CI/CD pipeline
16. **Monitor zip file generation** in the pipeline artifacts
17. **Monitor pipeline execution** in GitLab web interface
18. **Check SageMaker resources** in AWS console

## 🔐 Workspace Access Guide

### Accessing the Workspace Server

The workspace server provides multiple ways to access your development environment:

#### Method 1: SSH Access
```bash
ssh -i ~/.ssh/id_rsa ubuntu@35.90.17.111
# Password: workspace123!
```

#### Method 2: VS Code Server (Recommended)
1. Open your browser and navigate to: `http://35.90.17.111:8080`
2. Login with:
   - **Username**: `ubuntu`
   - **Password**: `workspace123!`
3. Start coding directly in your browser!

#### Method 3: RDP (Remote Desktop)
1. Use any RDP client
2. Connect to: `rdp://35.90.17.111:3389`
3. Login with:
   - **Username**: `ubuntu`
   - **Password**: `workspace123!`

#### Method 4: VNC
1. Use any VNC client
2. Connect to: `vnc://35.90.17.111:5900`
3. Login with:
   - **Username**: `ubuntu`
   - **Password**: `workspace123!`

### Accessing GitLab from Workspace

Once connected to the workspace, access GitLab:

1. **Web Interface**: Open `http://10.0.10.25` in your browser
2. **SSH Access**: Run `ssh ubuntu@10.0.10.25` from the workspace terminal
3. **Get GitLab Password**: Run `ssh ubuntu@10.0.10.25 "sudo cat /etc/gitlab/initial_root_password"`

### Security Notes
- GitLab is only accessible through the workspace server
- All traffic is encrypted and secured through security groups
- The workspace acts as a bastion host for secure access
- No direct internet access to GitLab server

## ⚙️ Configuration

### Infrastructure Configuration
All configuration is centralized in `locals.tf`. Key settings include:

- **Project Configuration**: Project name, environment
- **AWS Configuration**: Region (us-west-2), availability zones
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
├── src/                            # Source code
│   ├── training/
│   │   └── train.py                # Training script
│   ├── inference/
│   │   ├── inference.py            # Inference script
│   │   └── requirements.txt        # Dependencies
│   └── utils/                      # Utility functions
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
- **HTTP**: http://44.245.144.202
- **HTTPS**: https://44.245.144.202 (after SSL configuration)
- **Custom Domain**: gitlab.gitlab.local (Route53 configured)

### SSH Access
- **Server SSH**: `ssh -i ~/.ssh/id_rsa ubuntu@44.245.144.202`
- **Git SSH**: `git@44.245.144.202:`

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

### Common Issues and Solutions

#### 1. GitLab Not Accessible
**Symptoms**: Cannot access GitLab web interface
**Solutions**:
- Wait 5-10 minutes for GitLab to fully initialize
- Check security group allows HTTP/HTTPS traffic (ports 80, 443)
- Verify instance is running: `aws ec2 describe-instances --instance-ids i-090b1f4e1bae82322`
- Check GitLab status: `ssh -i ~/.ssh/id_rsa ubuntu@44.245.144.202 "sudo gitlab-ctl status"`

#### 2. SSH Connection Failed
**Symptoms**: Cannot SSH to GitLab server
**Solutions**:
- Verify SSH key permissions: `chmod 600 ~/.ssh/id_rsa`
- Check security group allows SSH traffic (ports 22, 2222)
- Ensure instance is running and accessible
- Try: `ssh -i ~/.ssh/id_rsa -v ubuntu@44.245.144.202` for verbose output

#### 3. Initial Password Not Found
**Symptoms**: Cannot find GitLab root password
**Solutions**:
- SSH into server: `ssh -i ~/.ssh/id_rsa ubuntu@44.245.144.202`
- Check password file: `sudo cat /etc/gitlab/initial_root_password`
- If file doesn't exist, wait for GitLab to complete initialization
- Use workspace task: "Get GitLab Root Password"

#### 4. OpenTofu Issues
**Symptoms**: OpenTofu commands fail
**Solutions**:
- Run `tofu init` to initialize providers
- Check AWS credentials: `aws sts get-caller-identity`
- Verify region and resource availability
- Check for syntax errors in configuration files

#### 5. Pipeline Failures
**Symptoms**: CI/CD pipeline fails
**Solutions**:
- Check GitLab CI/CD logs in web interface
- Verify AWS credentials and permissions
- Ensure SageMaker resources are available
- Check Python dependencies and script syntax
- Review security group rules for outbound traffic

#### 6. SageMaker Training Job Failures
**Symptoms**: Training jobs fail to start or complete
**Solutions**:
- Check IAM role permissions for SageMaker
- Verify S3 bucket access and permissions
- Review training script syntax and dependencies
- Check instance type availability in region
- Monitor CloudWatch logs for detailed error messages

#### 7. Model Endpoint Deployment Issues
**Symptoms**: Endpoints fail to deploy or respond
**Solutions**:
- Verify model artifacts are available in S3
- Check endpoint configuration and instance types
- Review security group rules for endpoint access
- Monitor endpoint health and logs
- Ensure sufficient IAM permissions

### Debug Commands

```bash
# Check GitLab status
ssh -i ~/.ssh/id_rsa ubuntu@44.245.144.202 "sudo gitlab-ctl status"

# View GitLab logs
ssh -i ~/.ssh/id_rsa ubuntu@44.245.144.202 "sudo gitlab-ctl tail"

# Check system resources
ssh -i ~/.ssh/id_rsa ubuntu@44.245.144.202 "htop"

# Verify AWS connectivity
aws sts get-caller-identity

# Check SageMaker resources
aws sagemaker list-training-jobs --region us-west-2

# Monitor CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/gitlab-server"
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