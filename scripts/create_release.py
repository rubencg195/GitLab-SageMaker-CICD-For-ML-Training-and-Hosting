#!/usr/bin/env python3
"""
Release Management Script
This script creates and manages candidate and stable releases.
"""

import argparse
import boto3
import json
import logging
from datetime import datetime
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ReleaseManager:
    def __init__(self, region: str = "us-east-1"):
        """Initialize AWS clients."""
        self.sagemaker_client = boto3.client('sagemaker', region_name=region)
        self.s3_client = boto3.client('s3', region_name=region)
        self.region = region

    def create_release_metadata(self, 
                              release_type: str,
                              version: str,
                              endpoint_name: str,
                              model_name: str,
                              additional_info: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Create release metadata.
        
        Args:
            release_type: Type of release (candidate or stable)
            version: Version of the release
            endpoint_name: Name of the endpoint
            model_name: Name of the model
            additional_info: Additional release information
            
        Returns:
            Release metadata dictionary
        """
        if additional_info is None:
            additional_info = {}

        # Get endpoint information
        try:
            endpoint_info = self.sagemaker_client.describe_endpoint(
                EndpointName=endpoint_name
            )
        except Exception as e:
            logger.error(f"Failed to get endpoint info: {str(e)}")
            endpoint_info = {}

        # Get model information
        try:
            model_info = self.sagemaker_client.describe_model(
                ModelName=model_name
            )
        except Exception as e:
            logger.error(f"Failed to get model info: {str(e)}")
            model_info = {}

        # Create release metadata
        release_metadata = {
            "release_type": release_type,
            "version": version,
            "endpoint_name": endpoint_name,
            "model_name": model_name,
            "creation_time": datetime.now().isoformat(),
            "endpoint_info": {
                "endpoint_arn": endpoint_info.get('EndpointArn', ''),
                "endpoint_status": endpoint_info.get('EndpointStatus', ''),
                "creation_time": endpoint_info.get('CreationTime', '').isoformat() if endpoint_info.get('CreationTime') else '',
                "last_modified_time": endpoint_info.get('LastModifiedTime', '').isoformat() if endpoint_info.get('LastModifiedTime') else ''
            },
            "model_info": {
                "model_arn": model_info.get('ModelArn', ''),
                "creation_time": model_info.get('CreationTime', '').isoformat() if model_info.get('CreationTime') else '',
                "containers": model_info.get('Containers', [])
            },
            "additional_info": additional_info
        }

        return release_metadata

    def save_release_metadata(self, 
                            release_metadata: Dict[str, Any],
                            s3_bucket: str = None) -> str:
        """
        Save release metadata to file and optionally to S3.
        
        Args:
            release_metadata: Release metadata dictionary
            s3_bucket: S3 bucket to save metadata (optional)
            
        Returns:
            Path where metadata was saved
        """
        # Create filename
        filename = f"release_{release_metadata['release_type']}_{release_metadata['version']}.json"
        
        # Save to local file
        with open(filename, 'w') as f:
            json.dump(release_metadata, f, indent=2)
        
        logger.info(f"Release metadata saved to: {filename}")
        
        # Save to S3 if bucket provided
        if s3_bucket:
            try:
                s3_key = f"releases/{filename}"
                self.s3_client.put_object(
                    Bucket=s3_bucket,
                    Key=s3_key,
                    Body=json.dumps(release_metadata, indent=2),
                    ContentType='application/json'
                )
                logger.info(f"Release metadata saved to S3: s3://{s3_bucket}/{s3_key}")
            except Exception as e:
                logger.error(f"Failed to save to S3: {str(e)}")
        
        return filename

    def create_release_notes(self, release_metadata: Dict[str, Any]) -> str:
        """
        Create release notes from metadata.
        
        Args:
            release_metadata: Release metadata dictionary
            
        Returns:
            Formatted release notes
        """
        release_type = release_metadata['release_type']
        version = release_metadata['version']
        endpoint_name = release_metadata['endpoint_name']
        model_name = release_metadata['model_name']
        creation_time = release_metadata['creation_time']
        
        release_notes = f"""
# {release_type.title()} Release - {version}

## Release Information
- **Type**: {release_type.title()}
- **Version**: {version}
- **Created**: {creation_time}
- **Endpoint**: {endpoint_name}
- **Model**: {model_name}

## Endpoint Details
- **Status**: {release_metadata['endpoint_info']['endpoint_status']}
- **ARN**: {release_metadata['endpoint_info']['endpoint_arn']}
- **Created**: {release_metadata['endpoint_info']['creation_time']}

## Model Details
- **ARN**: {release_metadata['model_info']['model_arn']}
- **Created**: {release_metadata['model_info']['creation_time']}

## Usage
To use this release, you can invoke the endpoint using the SageMaker Runtime API:

```python
import boto3

runtime = boto3.client('sagemaker-runtime', region_name='{self.region}')
response = runtime.invoke_endpoint(
    EndpointName='{endpoint_name}',
    ContentType='application/json',
    Body=json.dumps(your_data)
)
```

## Monitoring
Monitor the endpoint using CloudWatch metrics and logs. The endpoint is configured with auto-scaling and health monitoring.

## Support
For issues or questions, please contact the ML team or create an issue in the project repository.
"""
        
        return release_notes

    def create_git_tag(self, version: str, release_notes: str) -> None:
        """
        Create a Git tag for the release.
        
        Args:
            version: Version of the release
            release_notes: Release notes
        """
        try:
            import subprocess
            
            # Create annotated tag
            subprocess.run([
                'git', 'tag', '-a', version, '-m', release_notes
            ], check=True)
            
            logger.info(f"Git tag created: {version}")
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to create Git tag: {str(e)}")
        except FileNotFoundError:
            logger.warning("Git not found, skipping tag creation")

    def notify_release(self, 
                      release_metadata: Dict[str, Any],
                      webhook_url: str = None) -> None:
        """
        Send notification about the release.
        
        Args:
            release_metadata: Release metadata dictionary
            webhook_url: Webhook URL for notifications (optional)
        """
        if not webhook_url:
            logger.info("No webhook URL provided, skipping notification")
            return

        try:
            import requests
            
            # Prepare notification payload
            notification = {
                "text": f"New {release_metadata['release_type']} release created",
                "attachments": [
                    {
                        "color": "good" if release_metadata['release_type'] == 'stable' else "warning",
                        "fields": [
                            {
                                "title": "Version",
                                "value": release_metadata['version'],
                                "short": True
                            },
                            {
                                "title": "Type",
                                "value": release_metadata['release_type'].title(),
                                "short": True
                            },
                            {
                                "title": "Endpoint",
                                "value": release_metadata['endpoint_name'],
                                "short": True
                            },
                            {
                                "title": "Model",
                                "value": release_metadata['model_name'],
                                "short": True
                            }
                        ]
                    }
                ]
            }
            
            # Send notification
            response = requests.post(webhook_url, json=notification)
            response.raise_for_status()
            
            logger.info("Release notification sent successfully")
            
        except Exception as e:
            logger.error(f"Failed to send notification: {str(e)}")

def main():
    """Main function to handle command line arguments and execute release creation."""
    parser = argparse.ArgumentParser(description='Create and manage releases')
    
    parser.add_argument('--release-type', required=True, choices=['candidate', 'stable'], help='Type of release')
    parser.add_argument('--version', required=True, help='Version of the release')
    parser.add_argument('--endpoint-name', required=True, help='Name of the endpoint')
    parser.add_argument('--model-name', required=True, help='Name of the model')
    parser.add_argument('--s3-bucket', help='S3 bucket to save metadata')
    parser.add_argument('--webhook-url', help='Webhook URL for notifications')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--create-tag', action='store_true', help='Create Git tag for the release')
    
    args = parser.parse_args()
    
    # Create release manager instance
    release_manager = ReleaseManager(region=args.region)
    
    try:
        # Create release metadata
        release_metadata = release_manager.create_release_metadata(
            release_type=args.release_type,
            version=args.version,
            endpoint_name=args.endpoint_name,
            model_name=args.model_name
        )
        
        # Save release metadata
        filename = release_manager.save_release_metadata(
            release_metadata=release_metadata,
            s3_bucket=args.s3_bucket
        )
        
        # Create release notes
        release_notes = release_manager.create_release_notes(release_metadata)
        
        # Save release notes
        notes_filename = f"RELEASE_NOTES_{args.version}.md"
        with open(notes_filename, 'w') as f:
            f.write(release_notes)
        
        logger.info(f"Release notes saved to: {notes_filename}")
        
        # Create Git tag if requested
        if args.create_tag:
            release_manager.create_git_tag(args.version, release_notes)
        
        # Send notification
        release_manager.notify_release(
            release_metadata=release_metadata,
            webhook_url=args.webhook_url
        )
        
        print(f"Release created successfully!")
        print(f"Type: {args.release_type}")
        print(f"Version: {args.version}")
        print(f"Endpoint: {args.endpoint_name}")
        print(f"Model: {args.model_name}")
        print(f"Metadata file: {filename}")
        print(f"Release notes: {notes_filename}")
        
    except Exception as e:
        logger.error(f"Release creation failed: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()
