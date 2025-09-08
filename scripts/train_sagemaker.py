#!/usr/bin/env python3
"""
SageMaker XGBoost Training Script
This script creates and manages SageMaker training jobs using AWS pre-built XGBoost containers.
"""

import argparse
import boto3
import json
import logging
import os
import sys
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class XGBoostTrainer:
    def __init__(self, region='us-east-1'):
        """Initialize the XGBoost trainer."""
        self.region = region
        self.sagemaker_client = boto3.client('sagemaker', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
        
        # AWS pre-built XGBoost container URIs by region
        self.xgboost_containers = {
            'us-east-1': '683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-xgboost:1.7-1',
            'us-west-2': '433757028032.dkr.ecr.us-west-2.amazonaws.com/sagemaker-xgboost:1.7-1',
            'us-east-2': '257758044811.dkr.ecr.us-east-2.amazonaws.com/sagemaker-xgboost:1.7-1',
            'us-west-1': '433757028032.dkr.ecr.us-west-1.amazonaws.com/sagemaker-xgboost:1.7-1',
            'eu-west-1': '685385470294.dkr.ecr.eu-west-1.amazonaws.com/sagemaker-xgboost:1.7-1',
            'eu-central-1': '438346466558.dkr.ecr.eu-central-1.amazonaws.com/sagemaker-xgboost:1.7-1',
            'ap-southeast-1': '544295431143.dkr.ecr.ap-southeast-1.amazonaws.com/sagemaker-xgboost:1.7-1',
            'ap-southeast-2': '666831318237.dkr.ecr.ap-southeast-2.amazonaws.com/sagemaker-xgboost:1.7-1',
            'ap-northeast-1': '351501993468.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-xgboost:1.7-1',
            'ca-central-1': '469771592824.dkr.ecr.ca-central-1.amazonaws.com/sagemaker-xgboost:1.7-1'
        }
        
    def get_xgboost_container_uri(self) -> str:
        """Get the XGBoost container URI for the current region."""
        container_uri = self.xgboost_containers.get(self.region)
        if not container_uri:
            raise ValueError(f"XGBoost container not available for region: {self.region}")
        return container_uri
    
    def create_training_job(self, job_name: str, role_arn: str, s3_bucket: str,
                          instance_type: str = 'ml.m5.large', max_runtime: int = 3600,
                          hyperparameters: Dict[str, Any] = None) -> str:
        """Create a SageMaker XGBoost training job."""
        try:
            # Default hyperparameters for XGBoost
            default_hyperparameters = {
                'num_round': '100',
                'max_depth': '6',
                'eta': '0.3',
                'objective': 'reg:squarederror',
                'subsample': '0.8',
                'colsample_bytree': '0.8',
                'eval_metric': 'rmse',
                'early_stopping_rounds': '10'
            }
            
            if hyperparameters:
                default_hyperparameters.update(hyperparameters)
            
            # Get XGBoost container URI
            container_uri = self.get_xgboost_container_uri()
            logger.info(f"Using XGBoost container: {container_uri}")
            
            # Training job configuration
            training_job_config = {
                'TrainingJobName': job_name,
                'RoleArn': role_arn,
                'AlgorithmSpecification': {
                    'TrainingInputMode': 'File',
                    'TrainingImage': container_uri
                },
                'InputDataConfig': [
                    {
                        'ChannelName': 'training',
                        'DataSource': {
                            'S3DataSource': {
                                'S3DataType': 'S3Prefix',
                                'S3Uri': f's3://{s3_bucket}/training-data/',
                                'S3DataDistributionType': 'FullyReplicated'
                            }
                        },
                        'ContentType': 'text/csv'
                    },
                    {
                        'ChannelName': 'validation',
                        'DataSource': {
                            'S3DataSource': {
                                'S3DataType': 'S3Prefix',
                                'S3Uri': f's3://{s3_bucket}/validation-data/',
                                'S3DataDistributionType': 'FullyReplicated'
                            }
                        },
                        'ContentType': 'text/csv'
                    }
                ],
                'OutputDataConfig': {
                    'S3OutputPath': f's3://{s3_bucket}/models/{job_name}/'
                },
                'ResourceConfig': {
                    'InstanceType': instance_type,
                    'InstanceCount': 1,
                    'VolumeSizeInGB': 30
                },
                'StoppingCondition': {
                    'MaxRuntimeInSeconds': max_runtime
                },
                'HyperParameters': default_hyperparameters,
                'Tags': [
                    {
                        'Key': 'Project',
                        'Value': 'sagemaker-xgboost-ml'
                    },
                    {
                        'Key': 'Environment',
                        'Value': 'production'
                    },
                    {
                        'Key': 'Algorithm',
                        'Value': 'XGBoost'
                    }
                ]
            }
            
            logger.info(f"Creating XGBoost training job: {job_name}")
            response = self.sagemaker_client.create_training_job(**training_job_config)
            
            logger.info(f"Training job created successfully: {job_name}")
            logger.info(f"Training job ARN: {response['TrainingJobArn']}")
            
            return response['TrainingJobArn']
            
        except Exception as e:
            logger.error(f"Failed to create training job: {e}")
            raise
    
    def wait_for_training_job(self, job_name: str, max_wait_time: int = 3600) -> str:
        """Wait for training job to complete."""
        try:
            logger.info(f"Waiting for XGBoost training job to complete: {job_name}")
            
            waiter = self.sagemaker_client.get_waiter('training_job_completed_or_stopped')
            waiter.wait(
                TrainingJobName=job_name,
                WaiterConfig={
                    'Delay': 30,
                    'MaxAttempts': max_wait_time // 30
                }
            )
            
            # Get final status
            response = self.sagemaker_client.describe_training_job(TrainingJobName=job_name)
            status = response['TrainingJobStatus']
            
            if status == 'Completed':
                logger.info(f"XGBoost training job completed successfully: {job_name}")
                return status
            else:
                logger.error(f"Training job failed with status: {status}")
                logger.error(f"Failure reason: {response.get('FailureReason', 'Unknown')}")
                raise Exception(f"Training job failed: {status}")
                
        except Exception as e:
            logger.error(f"Error waiting for training job: {e}")
            raise
    
    def get_training_job_info(self, job_name: str) -> Dict[str, Any]:
        """Get training job information."""
        try:
            response = self.sagemaker_client.describe_training_job(TrainingJobName=job_name)
            
            return {
                'job_name': job_name,
                'status': response['TrainingJobStatus'],
                'creation_time': response['CreationTime'].isoformat(),
                'training_end_time': response.get('TrainingEndTime', '').isoformat() if response.get('TrainingEndTime') else None,
                'model_artifacts': response.get('ModelArtifacts', {}).get('S3ModelArtifacts', ''),
                'training_time': response.get('TrainingTimeInSeconds', 0),
                'hyperparameters': response.get('HyperParameters', {}),
                'algorithm_specification': response.get('AlgorithmSpecification', {}),
                'resource_config': response.get('ResourceConfig', {}),
                'output_data_config': response.get('OutputDataConfig', {}),
                'failure_reason': response.get('FailureReason', ''),
                'container_uri': response.get('AlgorithmSpecification', {}).get('TrainingImage', '')
            }
            
        except Exception as e:
            logger.error(f"Failed to get training job info: {e}")
            raise
    
    def list_training_jobs(self, max_results: int = 10) -> list:
        """List recent training jobs."""
        try:
            response = self.sagemaker_client.list_training_jobs(
                MaxResults=max_results,
                SortBy='CreationTime',
                SortOrder='Descending'
            )
            
            return response['TrainingJobSummaries']
            
        except Exception as e:
            logger.error(f"Failed to list training jobs: {e}")
            raise
    
    def save_training_metrics(self, job_name: str, output_file: str = 'training_metrics.json'):
        """Save training job metrics to file."""
        try:
            job_info = self.get_training_job_info(job_name)
            
            # Get training metrics from CloudWatch
            cloudwatch = boto3.client('cloudwatch', region_name=self.region)
            
            # Get various XGBoost metrics
            metrics_to_fetch = ['TrainLoss', 'ValidationLoss', 'TrainRMSE', 'ValidationRMSE']
            cloudwatch_metrics = {}
            
            for metric_name in metrics_to_fetch:
                try:
                    metrics = cloudwatch.get_metric_statistics(
                        Namespace='AWS/SageMaker/TrainingJobs',
                        MetricName=metric_name,
                        Dimensions=[
                            {
                                'Name': 'TrainingJobName',
                                'Value': job_name
                            }
                        ],
                        StartTime=datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0),
                        EndTime=datetime.utcnow(),
                        Period=300,
                        Statistics=['Average', 'Maximum', 'Minimum']
                    )
                    cloudwatch_metrics[metric_name] = metrics.get('Datapoints', [])
                except Exception as e:
                    logger.warning(f"Could not fetch metric {metric_name}: {e}")
                    cloudwatch_metrics[metric_name] = []
            
            job_info['cloudwatch_metrics'] = cloudwatch_metrics
            
            with open(output_file, 'w') as f:
                json.dump(job_info, f, indent=2, default=str)
            
            logger.info(f"XGBoost training metrics saved to: {output_file}")
            
        except Exception as e:
            logger.error(f"Failed to save training metrics: {e}")
            raise

def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Create and manage SageMaker XGBoost training jobs')
    parser.add_argument('--job-name', required=True,
                       help='Name of the training job')
    parser.add_argument('--role-arn', required=True,
                       help='IAM role ARN for SageMaker')
    parser.add_argument('--s3-bucket', required=True,
                       help='S3 bucket for training data and model artifacts')
    parser.add_argument('--instance-type', default='ml.m5.large',
                       help='EC2 instance type for training')
    parser.add_argument('--max-runtime', type=int, default=3600,
                       help='Maximum runtime in seconds')
    parser.add_argument('--num-round', type=int, default=100,
                       help='Number of boosting rounds')
    parser.add_argument('--max-depth', type=int, default=6,
                       help='Maximum depth of trees')
    parser.add_argument('--eta', type=float, default=0.3,
                       help='Learning rate')
    parser.add_argument('--objective', default='reg:squarederror',
                       help='XGBoost objective function')
    parser.add_argument('--subsample', type=float, default=0.8,
                       help='Subsample ratio')
    parser.add_argument('--colsample-bytree', type=float, default=0.8,
                       help='Column sample ratio')
    parser.add_argument('--eval-metric', default='rmse',
                       help='Evaluation metric')
    parser.add_argument('--early-stopping-rounds', type=int, default=10,
                       help='Early stopping rounds')
    parser.add_argument('--wait', action='store_true',
                       help='Wait for training job to complete')
    parser.add_argument('--region', default='us-east-1',
                       help='AWS region')
    parser.add_argument('--output-file', default='training_metrics.json',
                       help='Output file for training metrics')
    
    args = parser.parse_args()
    
    try:
        # Initialize trainer
        trainer = XGBoostTrainer(region=args.region)
        
        # Prepare hyperparameters
        hyperparameters = {
            'num_round': str(args.num_round),
            'max_depth': str(args.max_depth),
            'eta': str(args.eta),
            'objective': args.objective,
            'subsample': str(args.subsample),
            'colsample_bytree': str(args.colsample_bytree),
            'eval_metric': args.eval_metric,
            'early_stopping_rounds': str(args.early_stopping_rounds)
        }
        
        # Create training job
        job_arn = trainer.create_training_job(
            job_name=args.job_name,
            role_arn=args.role_arn,
            s3_bucket=args.s3_bucket,
            instance_type=args.instance_type,
            max_runtime=args.max_runtime,
            hyperparameters=hyperparameters
        )
        
        logger.info(f"XGBoost training job created: {job_arn}")
        
        # Wait for completion if requested
        if args.wait:
            status = trainer.wait_for_training_job(args.job_name)
            logger.info(f"Training job completed with status: {status}")
            
            # Save training metrics
            trainer.save_training_metrics(args.job_name, args.output_file)
        
        # Get and display job info
        job_info = trainer.get_training_job_info(args.job_name)
        logger.info(f"XGBoost training job info: {json.dumps(job_info, indent=2, default=str)}")
        
    except Exception as e:
        logger.error(f"FAILED: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()