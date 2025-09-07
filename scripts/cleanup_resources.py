#!/usr/bin/env python3
"""
Resource Cleanup Script
This script cleans up old SageMaker resources to manage costs.
"""

import argparse
import boto3
import json
import logging
from datetime import datetime, timedelta
from typing import List, Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ResourceCleanup:
    def __init__(self, region: str = "us-east-1"):
        """Initialize AWS clients."""
        self.sagemaker_client = boto3.client('sagemaker', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
        self.region = region

    def cleanup_old_training_jobs(self, 
                                 project_name: str,
                                 retention_days: int = 7,
                                 dry_run: bool = True) -> List[str]:
        """
        Clean up old training jobs.
        
        Args:
            project_name: Name of the project
            retention_days: Number of days to retain jobs
            dry_run: If True, only list jobs to be deleted
            
        Returns:
            List of deleted job names
        """
        try:
            # Calculate cutoff date
            cutoff_date = datetime.now() - timedelta(days=retention_days)
            
            # List training jobs
            response = self.sagemaker_client.list_training_jobs(
                NameContains=project_name,
                SortBy='CreationTime',
                SortOrder='Descending'
            )
            
            jobs_to_delete = []
            
            for job in response['TrainingJobSummaries']:
                job_name = job['TrainingJobName']
                creation_time = job['CreationTime']
                
                # Check if job is older than retention period
                if creation_time < cutoff_date:
                    # Only delete completed or failed jobs
                    if job['TrainingJobStatus'] in ['Completed', 'Failed', 'Stopped']:
                        jobs_to_delete.append(job_name)
            
            if dry_run:
                logger.info(f"Would delete {len(jobs_to_delete)} training jobs:")
                for job_name in jobs_to_delete:
                    logger.info(f"  - {job_name}")
                return []
            
            # Delete training jobs
            deleted_jobs = []
            for job_name in jobs_to_delete:
                try:
                    self.sagemaker_client.delete_training_job(
                        TrainingJobName=job_name
                    )
                    deleted_jobs.append(job_name)
                    logger.info(f"Deleted training job: {job_name}")
                except Exception as e:
                    logger.error(f"Failed to delete training job {job_name}: {str(e)}")
            
            return deleted_jobs
            
        except Exception as e:
            logger.error(f"Failed to cleanup training jobs: {str(e)}")
            raise

    def cleanup_old_endpoints(self, 
                            project_name: str,
                            retention_days: int = 7,
                            dry_run: bool = True) -> List[str]:
        """
        Clean up old endpoints.
        
        Args:
            project_name: Name of the project
            retention_days: Number of days to retain endpoints
            dry_run: If True, only list endpoints to be deleted
            
        Returns:
            List of deleted endpoint names
        """
        try:
            # Calculate cutoff date
            cutoff_date = datetime.now() - timedelta(days=retention_days)
            
            # List endpoints
            response = self.sagemaker_client.list_endpoints(
                NameContains=project_name,
                SortBy='CreationTime',
                SortOrder='Descending'
            )
            
            endpoints_to_delete = []
            
            for endpoint in response['Endpoints']:
                endpoint_name = endpoint['EndpointName']
                creation_time = endpoint['CreationTime']
                
                # Check if endpoint is older than retention period
                if creation_time < cutoff_date:
                    # Only delete endpoints that are not in service
                    if endpoint['EndpointStatus'] in ['Failed', 'OutOfService']:
                        endpoints_to_delete.append(endpoint_name)
            
            if dry_run:
                logger.info(f"Would delete {len(endpoints_to_delete)} endpoints:")
                for endpoint_name in endpoints_to_delete:
                    logger.info(f"  - {endpoint_name}")
                return []
            
            # Delete endpoints
            deleted_endpoints = []
            for endpoint_name in endpoints_to_delete:
                try:
                    self.sagemaker_client.delete_endpoint(
                        EndpointName=endpoint_name
                    )
                    deleted_endpoints.append(endpoint_name)
                    logger.info(f"Deleted endpoint: {endpoint_name}")
                except Exception as e:
                    logger.error(f"Failed to delete endpoint {endpoint_name}: {str(e)}")
            
            return deleted_endpoints
            
        except Exception as e:
            logger.error(f"Failed to cleanup endpoints: {str(e)}")
            raise

    def cleanup_old_models(self, 
                          project_name: str,
                          retention_days: int = 30,
                          dry_run: bool = True) -> List[str]:
        """
        Clean up old models.
        
        Args:
            project_name: Name of the project
            retention_days: Number of days to retain models
            dry_run: If True, only list models to be deleted
            
        Returns:
            List of deleted model names
        """
        try:
            # Calculate cutoff date
            cutoff_date = datetime.now() - timedelta(days=retention_days)
            
            # List models
            response = self.sagemaker_client.list_models(
                NameContains=project_name,
                SortBy='CreationTime',
                SortOrder='Descending'
            )
            
            models_to_delete = []
            
            for model in response['Models']:
                model_name = model['ModelName']
                creation_time = model['CreationTime']
                
                # Check if model is older than retention period
                if creation_time < cutoff_date:
                    models_to_delete.append(model_name)
            
            if dry_run:
                logger.info(f"Would delete {len(models_to_delete)} models:")
                for model_name in models_to_delete:
                    logger.info(f"  - {model_name}")
                return []
            
            # Delete models
            deleted_models = []
            for model_name in models_to_delete:
                try:
                    self.sagemaker_client.delete_model(
                        ModelName=model_name
                    )
                    deleted_models.append(model_name)
                    logger.info(f"Deleted model: {model_name}")
                except Exception as e:
                    logger.error(f"Failed to delete model {model_name}: {str(e)}")
            
            return deleted_models
            
        except Exception as e:
            logger.error(f"Failed to cleanup models: {str(e)}")
            raise

    def cleanup_old_model_packages(self, 
                                  project_name: str,
                                  retention_days: int = 30,
                                  dry_run: bool = True) -> List[str]:
        """
        Clean up old model packages.
        
        Args:
            project_name: Name of the project
            retention_days: Number of days to retain model packages
            dry_run: If True, only list model packages to be deleted
            
        Returns:
            List of deleted model package ARNs
        """
        try:
            # Calculate cutoff date
            cutoff_date = datetime.now() - timedelta(days=retention_days)
            
            # List model packages
            response = self.sagemaker_client.list_model_packages(
                NameContains=project_name,
                SortBy='CreationTime',
                SortOrder='Descending'
            )
            
            packages_to_delete = []
            
            for package in response['ModelPackageSummaryList']:
                package_arn = package['ModelPackageArn']
                creation_time = package['CreationTime']
                
                # Check if package is older than retention period
                if creation_time < cutoff_date:
                    # Only delete packages that are not approved
                    if package['ModelApprovalStatus'] in ['Rejected', 'PendingManualApproval']:
                        packages_to_delete.append(package_arn)
            
            if dry_run:
                logger.info(f"Would delete {len(packages_to_delete)} model packages:")
                for package_arn in packages_to_delete:
                    logger.info(f"  - {package_arn}")
                return []
            
            # Delete model packages
            deleted_packages = []
            for package_arn in packages_to_delete:
                try:
                    self.sagemaker_client.delete_model_package(
                        ModelPackageName=package_arn
                    )
                    deleted_packages.append(package_arn)
                    logger.info(f"Deleted model package: {package_arn}")
                except Exception as e:
                    logger.error(f"Failed to delete model package {package_arn}: {str(e)}")
            
            return deleted_packages
            
        except Exception as e:
            logger.error(f"Failed to cleanup model packages: {str(e)}")
            raise

    def cleanup_s3_artifacts(self, 
                           s3_bucket: str,
                           prefix: str,
                           retention_days: int = 30,
                           dry_run: bool = True) -> List[str]:
        """
        Clean up old S3 artifacts.
        
        Args:
            s3_bucket: S3 bucket name
            prefix: S3 prefix to clean up
            retention_days: Number of days to retain artifacts
            dry_run: If True, only list objects to be deleted
            
        Returns:
            List of deleted object keys
        """
        try:
            # Calculate cutoff date
            cutoff_date = datetime.now() - timedelta(days=retention_days)
            
            # List objects
            response = self.s3_client.list_objects_v2(
                Bucket=s3_bucket,
                Prefix=prefix
            )
            
            objects_to_delete = []
            
            if 'Contents' in response:
                for obj in response['Contents']:
                    key = obj['Key']
                    last_modified = obj['LastModified']
                    
                    # Check if object is older than retention period
                    if last_modified < cutoff_date:
                        objects_to_delete.append(key)
            
            if dry_run:
                logger.info(f"Would delete {len(objects_to_delete)} S3 objects:")
                for key in objects_to_delete:
                    logger.info(f"  - s3://{s3_bucket}/{key}")
                return []
            
            # Delete objects
            deleted_objects = []
            for key in objects_to_delete:
                try:
                    self.s3_client.delete_object(
                        Bucket=s3_bucket,
                        Key=key
                    )
                    deleted_objects.append(key)
                    logger.info(f"Deleted S3 object: s3://{s3_bucket}/{key}")
                except Exception as e:
                    logger.error(f"Failed to delete S3 object {key}: {str(e)}")
            
            return deleted_objects
            
        except Exception as e:
            logger.error(f"Failed to cleanup S3 artifacts: {str(e)}")
            raise

    def run_cleanup(self, 
                   project_name: str,
                   retention_days: int = 7,
                   s3_bucket: str = None,
                   dry_run: bool = True) -> Dict[str, List[str]]:
        """
        Run comprehensive cleanup.
        
        Args:
            project_name: Name of the project
            retention_days: Number of days to retain resources
            s3_bucket: S3 bucket to clean up (optional)
            dry_run: If True, only list resources to be deleted
            
        Returns:
            Dictionary containing cleanup results
        """
        results = {
            "training_jobs": [],
            "endpoints": [],
            "models": [],
            "model_packages": [],
            "s3_objects": []
        }
        
        try:
            logger.info(f"Starting cleanup for project: {project_name}")
            logger.info(f"Retention period: {retention_days} days")
            logger.info(f"Dry run: {dry_run}")
            
            # Cleanup training jobs
            results["training_jobs"] = self.cleanup_old_training_jobs(
                project_name=project_name,
                retention_days=retention_days,
                dry_run=dry_run
            )
            
            # Cleanup endpoints
            results["endpoints"] = self.cleanup_old_endpoints(
                project_name=project_name,
                retention_days=retention_days,
                dry_run=dry_run
            )
            
            # Cleanup models (longer retention)
            results["models"] = self.cleanup_old_models(
                project_name=project_name,
                retention_days=retention_days * 4,  # 4x longer retention for models
                dry_run=dry_run
            )
            
            # Cleanup model packages (longer retention)
            results["model_packages"] = self.cleanup_old_model_packages(
                project_name=project_name,
                retention_days=retention_days * 4,  # 4x longer retention for model packages
                dry_run=dry_run
            )
            
            # Cleanup S3 artifacts if bucket provided
            if s3_bucket:
                results["s3_objects"] = self.cleanup_s3_artifacts(
                    s3_bucket=s3_bucket,
                    prefix=f"training-output/{project_name}/",
                    retention_days=retention_days,
                    dry_run=dry_run
                )
            
            # Log summary
            total_resources = sum(len(resources) for resources in results.values())
            logger.info(f"Cleanup completed. Total resources processed: {total_resources}")
            
            return results
            
        except Exception as e:
            logger.error(f"Cleanup failed: {str(e)}")
            raise

def main():
    """Main function to handle command line arguments and execute cleanup."""
    parser = argparse.ArgumentParser(description='Clean up old SageMaker resources')
    
    parser.add_argument('--project-name', required=True, help='Name of the project')
    parser.add_argument('--retention-days', type=int, default=7, help='Number of days to retain resources')
    parser.add_argument('--s3-bucket', help='S3 bucket to clean up')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--dry-run', action='store_true', help='Only list resources to be deleted')
    
    args = parser.parse_args()
    
    # Create cleanup instance
    cleanup = ResourceCleanup(region=args.region)
    
    try:
        # Run cleanup
        results = cleanup.run_cleanup(
            project_name=args.project_name,
            retention_days=args.retention_days,
            s3_bucket=args.s3_bucket,
            dry_run=args.dry_run
        )
        
        # Print results
        print(f"Cleanup Results for {args.project_name}:")
        print(f"Training Jobs: {len(results['training_jobs'])}")
        print(f"Endpoints: {len(results['endpoints'])}")
        print(f"Models: {len(results['models'])}")
        print(f"Model Packages: {len(results['model_packages'])}")
        print(f"S3 Objects: {len(results['s3_objects'])}")
        
        # Save results to file
        with open('cleanup_results.json', 'w') as f:
            json.dump(results, f, indent=2)
        
        print("Cleanup results saved to: cleanup_results.json")
        
    except Exception as e:
        logger.error(f"Cleanup failed: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()
