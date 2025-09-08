#!/usr/bin/env python3
"""
Build Training Image Script for SageMaker
This script builds and pushes a Docker image for SageMaker training jobs.
"""

import argparse
import boto3
import docker
import json
import logging
import os
import sys
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class TrainingImageBuilder:
    def __init__(self, region='us-east-1', account_id=None):
        """Initialize the training image builder."""
        self.region = region
        self.account_id = account_id or self._get_account_id()
        self.ecr_client = boto3.client('ecr', region_name=region)
        self.docker_client = docker.from_env()
        
    def _get_account_id(self):
        """Get AWS account ID."""
        try:
            sts_client = boto3.client('sts')
            return sts_client.get_caller_identity()['Account']
        except Exception as e:
            logger.error(f"Failed to get account ID: {e}")
            raise
    
    def create_ecr_repository(self, repository_name):
        """Create ECR repository if it doesn't exist."""
        try:
            self.ecr_client.describe_repositories(repositoryNames=[repository_name])
            logger.info(f"ECR repository '{repository_name}' already exists")
        except self.ecr_client.exceptions.RepositoryNotFoundException:
            logger.info(f"Creating ECR repository '{repository_name}'")
            self.ecr_client.create_repository(
                repositoryName=repository_name,
                imageScanningConfiguration={'scanOnPush': True}
            )
            logger.info(f"ECR repository '{repository_name}' created successfully")
    
    def get_ecr_login_token(self):
        """Get ECR login token."""
        try:
            response = self.ecr_client.get_authorization_token()
            token = response['authorizationData'][0]['authorizationToken']
            endpoint = response['authorizationData'][0]['proxyEndpoint']
            return token, endpoint
        except Exception as e:
            logger.error(f"Failed to get ECR login token: {e}")
            raise
    
    def build_image(self, dockerfile_path, image_tag, build_context="."):
        """Build Docker image."""
        try:
            logger.info(f"Building Docker image with tag: {image_tag}")
            
            # Build the image
            image, build_logs = self.docker_client.images.build(
                path=build_context,
                dockerfile=dockerfile_path,
                tag=image_tag,
                rm=True,
                forcerm=True
            )
            
            # Log build output
            for log in build_logs:
                if 'stream' in log:
                    logger.info(log['stream'].strip())
            
            logger.info(f"Image built successfully: {image_tag}")
            return image
            
        except Exception as e:
            logger.error(f"Failed to build image: {e}")
            raise
    
    def push_image(self, image_tag, repository_uri):
        """Push image to ECR."""
        try:
            logger.info(f"Pushing image to ECR: {repository_uri}")
            
            # Tag image for ECR
            self.docker_client.images.get(image_tag).tag(repository_uri)
            
            # Push image
            push_logs = self.docker_client.images.push(repository_uri, stream=True, decode=True)
            
            for log in push_logs:
                if 'status' in log:
                    logger.info(f"{log['status']}: {log.get('progress', '')}")
                if 'error' in log:
                    logger.error(f"Push error: {log['error']}")
                    raise Exception(f"Failed to push image: {log['error']}")
            
            logger.info(f"Image pushed successfully to: {repository_uri}")
            
        except Exception as e:
            logger.error(f"Failed to push image: {e}")
            raise
    
    def login_to_ecr(self):
        """Login to ECR."""
        try:
            token, endpoint = self.get_ecr_login_token()
            
            # Decode token
            import base64
            username, password = base64.b64decode(token).decode().split(':')
            
            # Login to Docker registry
            self.docker_client.login(
                username=username,
                password=password,
                registry=endpoint
            )
            
            logger.info("Successfully logged in to ECR")
            
        except Exception as e:
            logger.error(f"Failed to login to ECR: {e}")
            raise
    
    def build_and_push(self, project_name, dockerfile_path="templates/sagemaker-training-job/Dockerfile", 
                      build_context="templates/sagemaker-training-job"):
        """Build and push training image."""
        try:
            # Repository configuration
            repository_name = f"{project_name}-training"
            image_tag = f"{repository_name}:latest"
            repository_uri = f"{self.account_id}.dkr.ecr.{self.region}.amazonaws.com/{repository_name}:latest"
            
            # Create ECR repository
            self.create_ecr_repository(repository_name)
            
            # Login to ECR
            self.login_to_ecr()
            
            # Build image
            self.build_image(dockerfile_path, image_tag, build_context)
            
            # Push image
            self.push_image(image_tag, repository_uri)
            
            # Save image URI for later use
            self.save_image_uri(repository_uri)
            
            logger.info(f"Training image build and push completed: {repository_uri}")
            return repository_uri
            
        except Exception as e:
            logger.error(f"Failed to build and push image: {e}")
            raise
    
    def save_image_uri(self, image_uri):
        """Save image URI to file for CI/CD pipeline."""
        try:
            with open('training_image_uri.txt', 'w') as f:
                f.write(image_uri)
            
            # Also save as JSON for programmatic access
            image_info = {
                'image_uri': image_uri,
                'timestamp': str(os.environ.get('CI_PIPELINE_CREATED_AT', 'local')),
                'commit_sha': os.environ.get('CI_COMMIT_SHA', 'unknown'),
                'project_name': os.environ.get('CI_PROJECT_NAME', 'local-project')
            }
            
            with open('training_image_info.json', 'w') as f:
                json.dump(image_info, f, indent=2)
            
            logger.info(f"Image URI saved: {image_uri}")
            
        except Exception as e:
            logger.error(f"Failed to save image URI: {e}")
            raise

def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Build and push SageMaker training image')
    parser.add_argument('--project-name', default=os.environ.get('CI_PROJECT_NAME', 'sagemaker-ml'),
                       help='Project name for the training image')
    parser.add_argument('--dockerfile-path', default='templates/sagemaker-training-job/Dockerfile',
                       help='Path to Dockerfile')
    parser.add_argument('--build-context', default='templates/sagemaker-training-job',
                       help='Build context directory')
    parser.add_argument('--region', default='us-east-1',
                       help='AWS region')
    parser.add_argument('--account-id', 
                       help='AWS account ID (auto-detected if not provided)')
    
    args = parser.parse_args()
    
    try:
        # Initialize builder
        builder = TrainingImageBuilder(region=args.region, account_id=args.account_id)
        
        # Build and push image
        image_uri = builder.build_and_push(
            project_name=args.project_name,
            dockerfile_path=args.dockerfile_path,
            build_context=args.build_context
        )
        
        logger.info(f"SUCCESS: Training image ready at {image_uri}")
        
    except Exception as e:
        logger.error(f"FAILED: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
