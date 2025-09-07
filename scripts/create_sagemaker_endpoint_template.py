#!/usr/bin/env python3
"""
Create SageMaker Endpoint Hosting Template
This script creates a new project based on the SageMaker endpoint hosting template.
"""

import argparse
import json
import os
import shutil
from pathlib import Path
from datetime import datetime


def create_endpoint_template(project_name, output_dir="."):
    """
    Create a new SageMaker endpoint hosting project from template
    """
    template_dir = Path("templates/sagemaker-endpoint-hosting")
    project_dir = Path(output_dir) / project_name
    
    if not template_dir.exists():
        print(f"Error: Template directory {template_dir} not found!")
        return False
    
    if project_dir.exists():
        print(f"Error: Project directory {project_dir} already exists!")
        return False
    
    try:
        # Create project directory
        project_dir.mkdir(parents=True, exist_ok=True)
        
        # Copy template files
        for file_path in template_dir.rglob("*"):
            if file_path.is_file():
                relative_path = file_path.relative_to(template_dir)
                dest_path = project_dir / relative_path
                dest_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(file_path, dest_path)
                print(f"Created: {dest_path}")
        
        # Update manifest with project-specific information
        manifest_path = project_dir / "manifest.json"
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
        
        manifest["project_name"] = project_name
        manifest["created_at"] = datetime.now().isoformat()
        manifest["ci_cd_config"]["zip_naming"] = f"candidate-PR-{{PR_ID}}-{{COMMIT_ID}}-{project_name}-{{TIMESTAMP}}.zip"
        manifest["ci_cd_config"]["stable_zip_naming"] = f"stable-{project_name}-{{TIMESTAMP}}.zip"
        
        with open(manifest_path, 'w') as f:
            json.dump(manifest, f, indent=2)
        
        # Create .gitlab-ci.yml for the project
        create_gitlab_ci(project_dir, project_name)
        
        # Create README for the project
        create_readme(project_dir, project_name)
        
        print(f"\n✅ SageMaker endpoint hosting template created successfully!")
        print(f"📁 Project directory: {project_dir.absolute()}")
        print(f"\n📋 Next steps:")
        print(f"1. cd {project_dir}")
        print(f"2. git init")
        print(f"3. git add .")
        print(f"4. git commit -m 'Initial commit'")
        print(f"5. Push to GitLab to trigger CI/CD pipeline")
        
        return True
        
    except Exception as e:
        print(f"Error creating template: {e}")
        return False


def create_gitlab_ci(project_dir, project_name):
    """Create GitLab CI configuration for the project"""
    ci_content = f"""# GitLab CI/CD Pipeline for {project_name}
# SageMaker Endpoint Hosting Project

stages:
  - validate
  - build
  - deploy
  - test
  - package
  - release

variables:
  PROJECT_NAME: "{project_name}"
  AWS_DEFAULT_REGION: "us-west-2"
  SAGEMAKER_ROLE_ARN: "$SAGEMAKER_ROLE_ARN"
  S3_BUCKET: "$S3_BUCKET"

# Cache Python dependencies
cache:
  paths:
    - .venv/
    - __pycache__/
    - .pytest_cache/

# Base image for all jobs
image: python:3.8

# Stage 1: Code Validation
validate_code:
  stage: validate
  before_script:
    - pip install --upgrade pip
    - pip install flake8 black pytest
  script:
    - echo "Validating code quality..."
    - flake8 src/ --max-line-length=88 --extend-ignore=E203,W503
    - black --check src/
    - python -m pytest tests/ -v
  only:
    - branches
    - merge_requests

# Stage 2: Build Inference Image
build_inference_image:
  stage: build
  before_script:
    - pip install boto3 sagemaker
  script:
    - echo "Building inference container..."
    - python scripts/build_inference_image.py
    - echo "Inference image built successfully"
  artifacts:
    paths:
      - inference_image_uri.txt
    expire_in: 1 hour
  only:
    - branches
    - merge_requests

# Stage 3: Deploy Endpoint
deploy_endpoint:
  stage: deploy
  before_script:
    - pip install boto3 sagemaker
    - export ENDPOINT_NAME="${{PROJECT_NAME}}-candidate-${{CI_COMMIT_SHORT_SHA}}"
  script:
    - echo "Deploying endpoint: $ENDPOINT_NAME"
    - python scripts/deploy_endpoint.py
        --endpoint-name $ENDPOINT_NAME
        --role-arn $SAGEMAKER_ROLE_ARN
        --s3-bucket $S3_BUCKET
        --instance-type ml.t2.medium
        --initial-instance-count 1
    - echo "Endpoint deployed successfully"
  artifacts:
    paths:
      - endpoint_config.json
    expire_in: 1 week
  only:
    - branches
    - merge_requests

# Stage 4: Test Endpoint
test_endpoint:
  stage: test
  before_script:
    - pip install boto3 requests pytest
    - export ENDPOINT_NAME="${{PROJECT_NAME}}-candidate-${{CI_COMMIT_SHORT_SHA}}"
  script:
    - echo "Testing endpoint: $ENDPOINT_NAME"
    - python scripts/test_endpoint.py
        --endpoint-name $ENDPOINT_NAME
        --test-data s3://$S3_BUCKET/test-data/
        --max-latency 1000
        --min-accuracy 0.85
    - echo "Endpoint tests passed"
  dependencies:
    - deploy_endpoint
  only:
    - branches
    - merge_requests

# Stage 5: Package Creation
package_zip:
  stage: package
  before_script:
    - pip install boto3
    - export ZIP_NAME="candidate-PR-${{CI_MERGE_REQUEST_IID:-${{CI_COMMIT_REF_SLUG}}}-${{CI_COMMIT_SHORT_SHA}}-${{PROJECT_NAME}}-$(date +%Y%m%d-%H%M%S).zip"
  script:
    - echo "Creating zip package: $ZIP_NAME"
    - python scripts/create_zip_package.py
        --zip-name $ZIP_NAME
        --release-type candidate
        --pr-id ${{CI_MERGE_REQUEST_IID:-"local"}}
        --commit-id ${{CI_COMMIT_SHORT_SHA}}
        --project-type inference
        --endpoint-name $ENDPOINT_NAME
    - echo "Zip package created: $ZIP_NAME"
  artifacts:
    paths:
      - "*.zip"
    expire_in: 1 week
  dependencies:
    - test_endpoint
  only:
    - branches
    - merge_requests

# Stage 6: Release Management
create_release:
  stage: release
  before_script:
    - pip install boto3
  script:
    - echo "Creating release..."
    - python scripts/create_release.py
        --release-type candidate
        --version "candidate-${{CI_COMMIT_SHORT_SHA}}"
        --project-name ${{PROJECT_NAME}}
    - echo "Release created successfully"
  dependencies:
    - package_zip
  only:
    - branches
    - merge_requests
"""
    
    ci_path = project_dir / ".gitlab-ci.yml"
    with open(ci_path, 'w') as f:
        f.write(ci_content)
    print(f"Created: {ci_path}")


def create_readme(project_dir, project_name):
    """Create README for the project"""
    readme_content = f"""# {project_name}

SageMaker Endpoint Hosting Project

## Overview
This project contains a SageMaker endpoint hosting implementation with automated CI/CD pipeline.

## Project Structure
```
{project_name}/
├── manifest.json              # Project configuration and CI/CD metadata
├── inference_handler.py       # Main inference handler
├── requirements.txt           # Python dependencies
├── Dockerfile                 # Container configuration
├── .gitlab-ci.yml            # CI/CD pipeline configuration
├── README.md                 # This file
└── scripts/                  # Automation scripts
    ├── build_inference_image.py
    ├── deploy_endpoint.py
    ├── test_endpoint.py
    ├── create_zip_package.py
    └── create_release.py
```

## Getting Started

1. **Configure AWS credentials** in GitLab CI/CD variables:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `SAGEMAKER_ROLE_ARN`
   - `S3_BUCKET`

2. **Customize the inference handler** (`inference_handler.py`):
   - Replace the placeholder model with your actual model
   - Update input/output processing logic
   - Modify prediction logic as needed

3. **Update dependencies** (`requirements.txt`):
   - Add any additional Python packages needed

4. **Push to GitLab** to trigger the CI/CD pipeline

## CI/CD Pipeline

The pipeline automatically:
- Validates code quality
- Builds inference container
- Deploys SageMaker endpoint
- Tests endpoint functionality
- Creates zip package with artifacts
- Manages releases

## Zip Package Contents

Each pipeline run creates a zip file containing:
- Source code and inference scripts
- Endpoint configurations
- Deployment configurations
- Documentation and metadata

## Support

For questions or issues, refer to the main project documentation.
"""
    
    readme_path = project_dir / "README.md"
    with open(readme_path, 'w') as f:
        f.write(readme_content)
    print(f"Created: {readme_path}")


def main():
    parser = argparse.ArgumentParser(description='Create SageMaker Endpoint Hosting Template')
    parser.add_argument('project_name', help='Name of the new project')
    parser.add_argument('--output-dir', default='.', help='Output directory for the project')
    
    args = parser.parse_args()
    
    success = create_endpoint_template(args.project_name, args.output_dir)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
