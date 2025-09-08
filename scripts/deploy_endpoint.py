#!/usr/bin/env python3
"""
SageMaker XGBoost Endpoint Deployment Script
This script deploys XGBoost models to SageMaker endpoints using AWS pre-built containers.
"""

import argparse
import boto3
import json
import logging
import time
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class XGBoostEndpointDeployer:
    def __init__(self, region: str = "us-east-1"):
        """Initialize SageMaker client and session."""
        self.sagemaker_client = boto3.client('sagemaker', region_name=region)
        self.region = region
        
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

    def create_model(self, 
                    model_name: str,
                    model_artifact_path: str,
                    execution_role_arn: str) -> str:
        """
        Create a SageMaker XGBoost model from training artifacts.
        
        Args:
            model_name: Name of the model
            model_artifact_path: S3 path to model artifacts
            execution_role_arn: IAM role ARN for execution
            
        Returns:
            Model ARN
        """
        try:
            # Get XGBoost container URI
            container_uri = self.get_xgboost_container_uri()
            logger.info(f"Using XGBoost container: {container_uri}")
            
            response = self.sagemaker_client.create_model(
                ModelName=model_name,
                ExecutionRoleArn=execution_role_arn,
                Containers=[
                    {
                        "Image": container_uri,
                        "ModelDataUrl": model_artifact_path,
                        "Environment": {
                            "SAGEMAKER_PROGRAM": "inference.py",
                            "SAGEMAKER_SUBMIT_DIRECTORY": "/opt/ml/code",
                            "SAGEMAKER_CONTAINER_LOG_LEVEL": "20",
                            "SAGEMAKER_REGION": self.region
                        }
                    }
                ],
                Tags=[
                    {
                        "Key": "Project",
                        "Value": "sagemaker-xgboost-ml"
                    },
                    {
                        "Key": "Environment",
                        "Value": "production"
                    },
                    {
                        "Key": "Algorithm",
                        "Value": "XGBoost"
                    }
                ]
            )
            
            model_arn = response['ModelArn']
            logger.info(f"XGBoost model created successfully: {model_arn}")
            return model_arn
            
        except Exception as e:
            logger.error(f"Failed to create XGBoost model: {str(e)}")
            raise

    def create_endpoint_config(self, 
                             config_name: str,
                             model_name: str,
                             instance_type: str = "ml.t2.medium",
                             initial_instance_count: int = 1,
                             max_instance_count: int = 2,
                             enable_auto_scaling: bool = False) -> str:
        """
        Create an endpoint configuration.
        
        Args:
            config_name: Name of the endpoint configuration
            model_name: Name of the model
            instance_type: EC2 instance type
            initial_instance_count: Initial number of instances
            max_instance_count: Maximum number of instances
            enable_auto_scaling: Whether to enable auto-scaling
            
        Returns:
            Endpoint configuration ARN
        """
        try:
            # Base production variant configuration
            production_variants = [
                {
                    "VariantName": "primary",
                    "ModelName": model_name,
                    "InitialInstanceCount": initial_instance_count,
                    "InstanceType": instance_type,
                    "InitialVariantWeight": 1.0
                }
            ]
            
            # Add auto-scaling configuration if enabled
            if enable_auto_scaling:
                production_variants[0]["AutoScaling"] = {
                    "MinCapacity": initial_instance_count,
                    "MaxCapacity": max_instance_count,
                    "TargetValue": 70.0,  # Target CPU utilization
                    "ScaleInCooldown": 300,  # 5 minutes
                    "ScaleOutCooldown": 300  # 5 minutes
                }
            
            response = self.sagemaker_client.create_endpoint_config(
                EndpointConfigName=config_name,
                ProductionVariants=production_variants,
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
                        "Key": "EndpointConfig",
                        "Value": config_name
                    }
                ]
            )
            
            config_arn = response['EndpointConfigArn']
            logger.info(f"Endpoint configuration created: {config_arn}")
            
            return config_arn
            
        except Exception as e:
            logger.error(f"Failed to create endpoint configuration: {str(e)}")
            raise

    def create_endpoint(self, 
                       endpoint_name: str,
                       config_name: str) -> str:
        """
        Create a SageMaker endpoint.
        
        Args:
            endpoint_name: Name of the endpoint
            config_name: Name of the endpoint configuration
            
        Returns:
            Endpoint ARN
        """
        try:
            response = self.sagemaker_client.create_endpoint(
                EndpointName=endpoint_name,
                EndpointConfigName=config_name,
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
                        "Key": "Endpoint",
                        "Value": endpoint_name
                    }
                ]
            )
            
            endpoint_arn = response['EndpointArn']
            logger.info(f"Endpoint created: {endpoint_arn}")
            
            return endpoint_arn
            
        except Exception as e:
            logger.error(f"Failed to create endpoint: {str(e)}")
            raise

    def update_endpoint(self, 
                       endpoint_name: str,
                       config_name: str) -> str:
        """
        Update an existing SageMaker endpoint.
        
        Args:
            endpoint_name: Name of the endpoint
            config_name: Name of the new endpoint configuration
            
        Returns:
            Endpoint ARN
        """
        try:
            response = self.sagemaker_client.update_endpoint(
                EndpointName=endpoint_name,
                EndpointConfigName=config_name
            )
            
            endpoint_arn = response['EndpointArn']
            logger.info(f"Endpoint updated: {endpoint_arn}")
            
            return endpoint_arn
            
        except Exception as e:
            logger.error(f"Failed to update endpoint: {str(e)}")
            raise

    def wait_for_endpoint(self, endpoint_name: str, timeout: int = 1800) -> str:
        """
        Wait for endpoint to be in service.
        
        Args:
            endpoint_name: Name of the endpoint
            timeout: Maximum wait time in seconds
            
        Returns:
            Final status of the endpoint
        """
        logger.info(f"Waiting for endpoint to be in service: {endpoint_name}")
        
        start_time = time.time()
        
        while True:
            try:
                response = self.sagemaker_client.describe_endpoint(
                    EndpointName=endpoint_name
                )
                
                status = response['EndpointStatus']
                logger.info(f"Endpoint status: {status}")
                
                if status in ['InService', 'Failed', 'OutOfService']:
                    if status == 'InService':
                        logger.info("Endpoint is now in service!")
                    else:
                        logger.error(f"Endpoint failed with status: {status}")
                        logger.error(f"Failure reason: {response.get('FailureReason', 'Unknown')}")
                    
                    return status
                
                # Check timeout
                if time.time() - start_time > timeout:
                    logger.error(f"Endpoint timed out after {timeout} seconds")
                    return 'Timeout'
                
                time.sleep(30)  # Wait 30 seconds before checking again
                
            except Exception as e:
                logger.error(f"Error checking endpoint status: {str(e)}")
                raise

    def get_endpoint_info(self, endpoint_name: str) -> Dict[str, Any]:
        """
        Get endpoint information.
        
        Args:
            endpoint_name: Name of the endpoint
            
        Returns:
            Dictionary containing endpoint information
        """
        try:
            response = self.sagemaker_client.describe_endpoint(
                EndpointName=endpoint_name
            )
            
            return {
                "endpoint_name": endpoint_name,
                "endpoint_arn": response['EndpointArn'],
                "endpoint_status": response['EndpointStatus'],
                "creation_time": response['CreationTime'].isoformat(),
                "last_modified_time": response['LastModifiedTime'].isoformat(),
                "production_variants": response.get('ProductionVariants', [])
            }
            
        except Exception as e:
            logger.error(f"Failed to get endpoint info: {str(e)}")
            raise

    def delete_endpoint(self, endpoint_name: str) -> None:
        """
        Delete an endpoint.
        
        Args:
            endpoint_name: Name of the endpoint to delete
        """
        try:
            self.sagemaker_client.delete_endpoint(EndpointName=endpoint_name)
            logger.info(f"Endpoint deleted: {endpoint_name}")
            
        except Exception as e:
            logger.error(f"Failed to delete endpoint: {str(e)}")
            raise

def main():
    """Main function to handle command line arguments and execute endpoint deployment."""
    parser = argparse.ArgumentParser(description='Deploy models to SageMaker endpoints')
    
    parser.add_argument('--endpoint-name', required=True, help='Name of the endpoint')
    parser.add_argument('--model-name', required=True, help='Name of the model')
    parser.add_argument('--model-artifact-path', help='S3 path to model artifacts (if not using model name)')
    parser.add_argument('--execution-role-arn', required=True, help='IAM role ARN for execution')
    parser.add_argument('--instance-type', default='ml.t2.medium', help='EC2 instance type')
    parser.add_argument('--initial-instance-count', type=int, default=1, help='Initial number of instances')
    parser.add_argument('--max-instance-count', type=int, default=2, help='Maximum number of instances')
    parser.add_argument('--enable-auto-scaling', action='store_true', help='Enable auto-scaling')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--wait', action='store_true', help='Wait for endpoint to be in service')
    parser.add_argument('--update', action='store_true', help='Update existing endpoint')
    
    args = parser.parse_args()
    
    # Create XGBoost deployer instance
    deployer = XGBoostEndpointDeployer(region=args.region)
    
    try:
        # Generate configuration name
        config_name = f"{args.endpoint_name}-config"
        
        if args.update:
            # Update existing endpoint
            logger.info(f"Updating endpoint: {args.endpoint_name}")
            
            # Create new endpoint configuration
            deployer.create_endpoint_config(
                config_name=config_name,
                model_name=args.model_name,
                instance_type=args.instance_type,
                initial_instance_count=args.initial_instance_count,
                max_instance_count=args.max_instance_count,
                enable_auto_scaling=args.enable_auto_scaling
            )
            
            # Update endpoint
            endpoint_arn = deployer.update_endpoint(
                endpoint_name=args.endpoint_name,
                config_name=config_name
            )
            
        else:
            # Create new endpoint
            logger.info(f"Creating new endpoint: {args.endpoint_name}")
            
            # Create XGBoost model if model artifact path is provided
            if args.model_artifact_path:
                deployer.create_model(
                    model_name=args.model_name,
                    model_artifact_path=args.model_artifact_path,
                    execution_role_arn=args.execution_role_arn
                )
            
            # Create endpoint configuration
            deployer.create_endpoint_config(
                config_name=config_name,
                model_name=args.model_name,
                instance_type=args.instance_type,
                initial_instance_count=args.initial_instance_count,
                max_instance_count=args.max_instance_count,
                enable_auto_scaling=args.enable_auto_scaling
            )
            
            # Create endpoint
            endpoint_arn = deployer.create_endpoint(
                endpoint_name=args.endpoint_name,
                config_name=config_name
            )
        
        print(f"Endpoint created/updated: {endpoint_arn}")
        
        # Wait for endpoint to be in service if requested
        if args.wait:
            status = deployer.wait_for_endpoint(args.endpoint_name)
            
            if status == 'InService':
                # Get endpoint info
                endpoint_info = deployer.get_endpoint_info(args.endpoint_name)
                print(f"Endpoint is in service!")
                print(f"Endpoint ARN: {endpoint_info['endpoint_arn']}")
                print(f"Creation time: {endpoint_info['creation_time']}")
                
                # Save endpoint info for CI/CD
                with open('endpoint_info.json', 'w') as f:
                    json.dump(endpoint_info, f, indent=2)
            else:
                print(f"Endpoint failed with status: {status}")
                exit(1)
        
    except Exception as e:
        logger.error(f"Endpoint deployment failed: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()
