#!/usr/bin/env python3
"""
SageMaker Model Registration Script
This script registers trained models in SageMaker Model Registry.
"""

import argparse
import boto3
import json
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ModelRegistry:
    def __init__(self, region: str = "us-east-1"):
        """Initialize SageMaker client and session."""
        self.sagemaker_client = boto3.client('sagemaker', region_name=region)
        self.region = region

    def create_model_package_group(self, group_name: str, description: str = None) -> str:
        """
        Create a model package group if it doesn't exist.
        
        Args:
            group_name: Name of the model package group
            description: Description of the model package group
            
        Returns:
            Model package group ARN
        """
        if description is None:
            description = f"Model package group for {group_name}"

        try:
            # Check if group already exists
            try:
                response = self.sagemaker_client.describe_model_package_group(
                    ModelPackageGroupName=group_name
                )
                logger.info(f"Model package group already exists: {group_name}")
                return response['ModelPackageGroupArn']
            except self.sagemaker_client.exceptions.ResourceNotFound:
                # Group doesn't exist, create it
                pass

            # Create model package group
            response = self.sagemaker_client.create_model_package_group(
                ModelPackageGroupName=group_name,
                ModelPackageGroupDescription=description,
                Tags=[
                    {
                        "Key": "Project",
                        "Value": "ml-training-pipeline"
                    },
                    {
                        "Key": "Environment",
                        "Value": "ci-cd"
                    }
                ]
            )
            
            logger.info(f"Model package group created: {response['ModelPackageGroupArn']}")
            return response['ModelPackageGroupArn']
            
        except Exception as e:
            logger.error(f"Failed to create model package group: {str(e)}")
            raise

    def get_training_job_info(self, training_job_name: str) -> Dict[str, Any]:
        """
        Get information from a completed training job.
        
        Args:
            training_job_name: Name of the training job
            
        Returns:
            Dictionary containing training job information
        """
        try:
            response = self.sagemaker_client.describe_training_job(
                TrainingJobName=training_job_name
            )
            
            if response['TrainingJobStatus'] != 'Completed':
                raise ValueError(f"Training job {training_job_name} is not completed")
            
            return {
                "model_artifacts": response['ModelArtifacts']['S3ModelArtifacts'],
                "training_image": response['AlgorithmSpecification']['TrainingImage'],
                "role_arn": response['RoleArn'],
                "creation_time": response['CreationTime'],
                "training_time": response.get('TrainingTimeInSeconds', 0),
                "final_metric_data": response.get('FinalMetricDataList', [])
            }
            
        except Exception as e:
            logger.error(f"Failed to get training job info: {str(e)}")
            raise

    def create_model_package(self, 
                           model_name: str,
                           training_job_name: str,
                           package_group_name: str,
                           model_version: str,
                           description: str = None) -> str:
        """
        Create a model package in the model registry.
        
        Args:
            model_name: Name of the model
            training_job_name: Name of the training job
            package_group_name: Name of the model package group
            model_version: Version of the model
            description: Description of the model package
            
        Returns:
            Model package ARN
        """
        if description is None:
            description = f"Model package for {model_name} version {model_version}"

        try:
            # Get training job information
            training_info = self.get_training_job_info(training_job_name)
            
            # Create model package
            response = self.sagemaker_client.create_model_package(
                ModelPackageName=model_name,
                ModelPackageGroupName=package_group_name,
                ModelPackageDescription=description,
                ModelPackageVersion=model_version,
                SourceAlgorithmSpecification={
                    "SourceAlgorithms": [
                        {
                            "AlgorithmName": training_job_name,
                            "ModelDataUrl": training_info["model_artifacts"]
                        }
                    ]
                },
                InferenceSpecification={
                    "Containers": [
                        {
                            "Image": training_info["training_image"],
                            "ModelDataUrl": training_info["model_artifacts"],
                            "Environment": {
                                "SAGEMAKER_PROGRAM": "inference.py",
                                "SAGEMAKER_SUBMIT_DIRECTORY": "/opt/ml/code",
                                "SAGEMAKER_CONTAINER_LOG_LEVEL": "20",
                                "SAGEMAKER_REGION": self.region
                            }
                        }
                    ],
                    "SupportedContentTypes": ["application/json", "text/csv"],
                    "SupportedResponseMIMETypes": ["application/json"],
                    "SupportedRealtimeInferenceInstanceTypes": [
                        "ml.t2.medium",
                        "ml.t2.large",
                        "ml.m5.large",
                        "ml.m5.xlarge"
                    ],
                    "SupportedTransformInstanceTypes": [
                        "ml.m5.large",
                        "ml.m5.xlarge",
                        "ml.c5.large",
                        "ml.c5.xlarge"
                    ]
                },
                ValidationSpecification={
                    "ValidationRole": training_info["role_arn"],
                    "ValidationProfiles": [
                        {
                            "ProfileName": "ValidationProfile1",
                            "TransformJobDefinition": {
                                "MaxPayloadInMB": 6,
                                "MaxConcurrentTransforms": 1,
                                "TransformInput": {
                                    "DataSource": {
                                        "S3DataSource": {
                                            "S3DataType": "S3Prefix",
                                            "S3Uri": "s3://your-validation-data-bucket/validation-data/"
                                        }
                                    },
                                    "ContentType": "text/csv"
                                },
                                "TransformOutput": {
                                    "S3OutputPath": "s3://your-validation-data-bucket/validation-output/"
                                },
                                "TransformResources": {
                                    "InstanceType": "ml.m5.large",
                                    "InstanceCount": 1
                                }
                            }
                        }
                    ]
                },
                Tags=[
                    {
                        "Key": "Project",
                        "Value": "ml-training-pipeline"
                    },
                    {
                        "Key": "Environment",
                        "Value": "ci-cd"
                    },
                    {
                        "Key": "ModelName",
                        "Value": model_name
                    },
                    {
                        "Key": "ModelVersion",
                        "Value": model_version
                    },
                    {
                        "Key": "TrainingJob",
                        "Value": training_job_name
                    }
                ]
            )
            
            model_package_arn = response['ModelPackageArn']
            logger.info(f"Model package created: {model_package_arn}")
            
            return model_package_arn
            
        except Exception as e:
            logger.error(f"Failed to create model package: {str(e)}")
            raise

    def approve_model_package(self, model_package_arn: str, approval_status: str = "Approved") -> None:
        """
        Approve a model package for deployment.
        
        Args:
            model_package_arn: ARN of the model package
            approval_status: Approval status (Approved, Rejected, PendingManualApproval)
        """
        try:
            self.sagemaker_client.update_model_package(
                ModelPackageArn=model_package_arn,
                ModelApprovalStatus=approval_status
            )
            
            logger.info(f"Model package {model_package_arn} approved with status: {approval_status}")
            
        except Exception as e:
            logger.error(f"Failed to approve model package: {str(e)}")
            raise

    def list_model_packages(self, package_group_name: str) -> List[Dict[str, Any]]:
        """
        List all model packages in a group.
        
        Args:
            package_group_name: Name of the model package group
            
        Returns:
            List of model package information
        """
        try:
            response = self.sagemaker_client.list_model_packages(
                ModelPackageGroupName=package_group_name,
                SortBy="CreationTime",
                SortOrder="Descending"
            )
            
            return response['ModelPackageSummaryList']
            
        except Exception as e:
            logger.error(f"Failed to list model packages: {str(e)}")
            raise

def main():
    """Main function to handle command line arguments and execute model registration."""
    parser = argparse.ArgumentParser(description='Register models in SageMaker Model Registry')
    
    parser.add_argument('--model-name', required=True, help='Name of the model')
    parser.add_argument('--training-job-name', required=True, help='Name of the training job')
    parser.add_argument('--package-group-name', required=True, help='Name of the model package group')
    parser.add_argument('--model-version', required=True, help='Version of the model')
    parser.add_argument('--description', help='Description of the model package')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--auto-approve', action='store_true', help='Automatically approve the model package')
    
    args = parser.parse_args()
    
    # Create model registry instance
    registry = ModelRegistry(region=args.region)
    
    try:
        # Create model package group if it doesn't exist
        registry.create_model_package_group(
            group_name=args.package_group_name,
            description=f"Model package group for {args.package_group_name}"
        )
        
        # Create model package
        model_package_arn = registry.create_model_package(
            model_name=args.model_name,
            training_job_name=args.training_job_name,
            package_group_name=args.package_group_name,
            model_version=args.model_version,
            description=args.description
        )
        
        print(f"Model package created: {model_package_arn}")
        
        # Auto-approve if requested
        if args.auto_approve:
            registry.approve_model_package(model_package_arn)
            print(f"Model package approved: {model_package_arn}")
        
        # Save model package info for CI/CD
        model_info = {
            "model_package_arn": model_package_arn,
            "model_name": args.model_name,
            "model_version": args.model_version,
            "package_group_name": args.package_group_name,
            "training_job_name": args.training_job_name,
            "creation_time": datetime.now().isoformat()
        }
        
        with open('model_package_info.json', 'w') as f:
            json.dump(model_info, f, indent=2)
        
        print("Model registration completed successfully!")
        
    except Exception as e:
        logger.error(f"Model registration failed: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()
