#!/usr/bin/env python3
"""
SageMaker Training Job Script
This script creates and manages SageMaker training jobs for ML models.
"""

import argparse
import boto3
import json
import time
import logging
from datetime import datetime
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SageMakerTrainer:
    def __init__(self, region: str = "us-east-1"):
        """Initialize SageMaker client and session."""
        self.sagemaker_client = boto3.client('sagemaker', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
        self.region = region

    def create_training_job(self, 
                          job_name: str,
                          role_arn: str,
                          s3_bucket: str,
                          instance_type: str = "ml.m5.large",
                          max_runtime: int = 3600,
                          hyperparameters: Dict[str, Any] = None) -> str:
        """
        Create a SageMaker training job.
        
        Args:
            job_name: Name of the training job
            role_arn: IAM role ARN for SageMaker
            s3_bucket: S3 bucket for data and outputs
            instance_type: EC2 instance type for training
            max_runtime: Maximum runtime in seconds
            hyperparameters: Training hyperparameters
            
        Returns:
            Training job ARN
        """
        if hyperparameters is None:
            hyperparameters = {
                "epochs": "10",
                "batch_size": "32",
                "learning_rate": "0.001"
            }

        # Prepare training data paths
        training_data_uri = f"s3://{s3_bucket}/training-data/"
        validation_data_uri = f"s3://{s3_bucket}/validation-data/"
        output_path = f"s3://{s3_bucket}/training-output/{job_name}/"

        # Training job configuration
        training_job_config = {
            "TrainingJobName": job_name,
            "RoleArn": role_arn,
            "AlgorithmSpecification": {
                "TrainingInputMode": "File",
                "TrainingImage": f"763104351884.dkr.ecr.{self.region}.amazonaws.com/pytorch-training:1.12.1-gpu-py38-cu113-ubuntu20.04-sagemaker",
                "EnableSageMakerMetricsTimeSeries": True
            },
            "InputDataConfig": [
                {
                    "ChannelName": "training",
                    "DataSource": {
                        "S3DataSource": {
                            "S3DataType": "S3Prefix",
                            "S3Uri": training_data_uri,
                            "S3DataDistributionType": "FullyReplicated"
                        }
                    },
                    "ContentType": "application/x-recordio-protobuf",
                    "CompressionType": "None"
                },
                {
                    "ChannelName": "validation",
                    "DataSource": {
                        "S3DataSource": {
                            "S3DataType": "S3Prefix",
                            "S3Uri": validation_data_uri,
                            "S3DataDistributionType": "FullyReplicated"
                        }
                    },
                    "ContentType": "application/x-recordio-protobuf",
                    "CompressionType": "None"
                }
            ],
            "OutputDataConfig": {
                "S3OutputPath": output_path
            },
            "ResourceConfig": {
                "InstanceType": instance_type,
                "InstanceCount": 1,
                "VolumeSizeInGB": 30
            },
            "StoppingCondition": {
                "MaxRuntimeInSeconds": max_runtime
            },
            "HyperParameters": hyperparameters,
            "Tags": [
                {
                    "Key": "Project",
                    "Value": "ml-training-pipeline"
                },
                {
                    "Key": "Environment",
                    "Value": "ci-cd"
                },
                {
                    "Key": "CreatedBy",
                    "Value": "gitlab-ci"
                }
            ]
        }

        try:
            logger.info(f"Creating training job: {job_name}")
            response = self.sagemaker_client.create_training_job(**training_job_config)
            
            training_job_arn = response['TrainingJobArn']
            logger.info(f"Training job created successfully: {training_job_arn}")
            
            return training_job_arn
            
        except Exception as e:
            logger.error(f"Failed to create training job: {str(e)}")
            raise

    def wait_for_training_job(self, job_name: str, timeout: int = 7200) -> str:
        """
        Wait for training job to complete.
        
        Args:
            job_name: Name of the training job
            timeout: Maximum wait time in seconds
            
        Returns:
            Final status of the training job
        """
        logger.info(f"Waiting for training job to complete: {job_name}")
        
        start_time = time.time()
        
        while True:
            try:
                response = self.sagemaker_client.describe_training_job(
                    TrainingJobName=job_name
                )
                
                status = response['TrainingJobStatus']
                logger.info(f"Training job status: {status}")
                
                if status in ['Completed', 'Failed', 'Stopped']:
                    if status == 'Completed':
                        logger.info("Training job completed successfully!")
                        logger.info(f"Model artifacts: {response.get('ModelArtifacts', {}).get('S3ModelArtifacts', 'N/A')}")
                    else:
                        logger.error(f"Training job failed with status: {status}")
                        logger.error(f"Failure reason: {response.get('FailureReason', 'Unknown')}")
                    
                    return status
                
                # Check timeout
                if time.time() - start_time > timeout:
                    logger.error(f"Training job timed out after {timeout} seconds")
                    return 'Timeout'
                
                time.sleep(30)  # Wait 30 seconds before checking again
                
            except Exception as e:
                logger.error(f"Error checking training job status: {str(e)}")
                raise

    def get_training_metrics(self, job_name: str) -> Dict[str, Any]:
        """
        Get training job metrics.
        
        Args:
            job_name: Name of the training job
            
        Returns:
            Dictionary containing training metrics
        """
        try:
            response = self.sagemaker_client.describe_training_job(
                TrainingJobName=job_name
            )
            
            metrics = {
                "job_name": job_name,
                "status": response['TrainingJobStatus'],
                "creation_time": response['CreationTime'].isoformat(),
                "training_time": response.get('TrainingTimeInSeconds', 0),
                "model_artifacts": response.get('ModelArtifacts', {}).get('S3ModelArtifacts', ''),
                "final_metric_data": response.get('FinalMetricDataList', [])
            }
            
            return metrics
            
        except Exception as e:
            logger.error(f"Failed to get training metrics: {str(e)}")
            raise

def main():
    """Main function to handle command line arguments and execute training."""
    parser = argparse.ArgumentParser(description='Create and manage SageMaker training jobs')
    
    parser.add_argument('--job-name', required=True, help='Name of the training job')
    parser.add_argument('--role-arn', required=True, help='IAM role ARN for SageMaker')
    parser.add_argument('--s3-bucket', required=True, help='S3 bucket for data and outputs')
    parser.add_argument('--instance-type', default='ml.m5.large', help='EC2 instance type')
    parser.add_argument('--max-runtime', type=int, default=3600, help='Maximum runtime in seconds')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--epochs', type=int, default=10, help='Number of training epochs')
    parser.add_argument('--batch-size', type=int, default=32, help='Training batch size')
    parser.add_argument('--learning-rate', type=float, default=0.001, help='Learning rate')
    parser.add_argument('--wait', action='store_true', help='Wait for training job to complete')
    
    args = parser.parse_args()
    
    # Create trainer instance
    trainer = SageMakerTrainer(region=args.region)
    
    # Prepare hyperparameters
    hyperparameters = {
        "epochs": str(args.epochs),
        "batch_size": str(args.batch_size),
        "learning_rate": str(args.learning_rate)
    }
    
    try:
        # Create training job
        training_job_arn = trainer.create_training_job(
            job_name=args.job_name,
            role_arn=args.role_arn,
            s3_bucket=args.s3_bucket,
            instance_type=args.instance_type,
            max_runtime=args.max_runtime,
            hyperparameters=hyperparameters
        )
        
        print(f"Training job created: {training_job_arn}")
        
        # Wait for completion if requested
        if args.wait:
            status = trainer.wait_for_training_job(args.job_name)
            
            if status == 'Completed':
                # Get and print metrics
                metrics = trainer.get_training_metrics(args.job_name)
                print(f"Training completed successfully!")
                print(f"Model artifacts: {metrics['model_artifacts']}")
                print(f"Training time: {metrics['training_time']} seconds")
                
                # Save metrics to file for CI/CD
                with open('training_metrics.json', 'w') as f:
                    json.dump(metrics, f, indent=2)
            else:
                print(f"Training job failed with status: {status}")
                exit(1)
        
    except Exception as e:
        logger.error(f"Training job failed: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()
