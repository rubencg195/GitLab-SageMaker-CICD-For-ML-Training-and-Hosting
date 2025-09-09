#!/usr/bin/env python3

import argparse
import boto3
import sys
import json
import os
from datetime import datetime

def main():
    parser = argparse.ArgumentParser(description='Create Release')
    parser.add_argument('--release-type', required=True, help='Release type')
    parser.add_argument('--version', required=True, help='Version')
    parser.add_argument('--endpoint-name', help='Endpoint name')
    parser.add_argument('--model-name', help='Model name')
    
    args = parser.parse_args()
    
    print(f"Creating {args.release_type} release: {args.version}")
    
    # Create release metadata
    release_metadata = {
        'release_type': args.release_type,
        'version': args.version,
        'endpoint_name': args.endpoint_name,
        'model_name': args.model_name,
        'created_at': datetime.utcnow().isoformat(),
        'commit_id': os.getenv('CI_COMMIT_SHA', 'unknown'),
        'pipeline_id': os.getenv('CI_PIPELINE_ID', 'unknown'),
        'pipeline_url': os.getenv('CI_PIPELINE_URL', 'unknown')
    }
    
    # Save to releases S3 bucket
    try:
        s3_client = boto3.client('s3')
        bucket_name = os.getenv('GITLAB_RELEASES_BUCKET')
        
        if bucket_name:
            key = f"releases/{args.release_type}/{args.version}/metadata.json"
            s3_client.put_object(
                Bucket=bucket_name,
                Key=key,
                Body=json.dumps(release_metadata, indent=2),
                ContentType='application/json'
            )
            print(f"✅ Release metadata uploaded to S3: s3://{bucket_name}/{key}")
        else:
            print("⚠️ GITLAB_RELEASES_BUCKET not set, skipping S3 upload")
            
    except Exception as e:
        print(f"⚠️ S3 upload failed: {e}")
    
    print(f"✅ Release {args.version} created successfully")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
