#!/usr/bin/env python3

import argparse
import boto3
import zipfile
import os
import sys
import json

def main():
    parser = argparse.ArgumentParser(description='Create ZIP package and upload to S3')
    parser.add_argument('--zip-name', required=True, help='ZIP file name')
    parser.add_argument('--release-type', required=True, help='Release type')
    parser.add_argument('--pr-id', help='PR ID')
    parser.add_argument('--commit-id', help='Commit ID')
    parser.add_argument('--endpoint-name', help='Endpoint name')
    parser.add_argument('--model-name', help='Model name')
    parser.add_argument('--training-output', help='Training output directory')
    
    args = parser.parse_args()
    
    print(f"Creating {args.release_type} ZIP package: {args.zip_name}")
    
    # Create ZIP package
    with zipfile.ZipFile(args.zip_name, 'w', zipfile.ZIP_DEFLATED) as zipf:
        # Add metadata
        metadata = {
            'release_type': args.release_type,
            'zip_name': args.zip_name,
            'commit_id': args.commit_id,
            'endpoint_name': args.endpoint_name,
            'model_name': args.model_name,
            'created_at': str(os.getenv('CI_COMMIT_TIMESTAMP', '2025-09-09'))
        }
        
        if args.pr_id:
            metadata['pr_id'] = args.pr_id
            
        zipf.writestr('metadata.json', json.dumps(metadata, indent=2))
        
        # Add training output if exists
        if args.training_output and os.path.exists(args.training_output):
            for root, dirs, files in os.walk(args.training_output):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, args.training_output)
                    zipf.write(file_path, f"training_output/{arcname}")
        
        # Add CI/CD configuration
        if os.path.exists('.gitlab-ci.yml'):
            zipf.write('.gitlab-ci.yml')
            
        # Add source code
        if os.path.exists('src'):
            for root, dirs, files in os.walk('src'):
                for file in files:
                    file_path = os.path.join(root, file)
                    arcname = os.path.relpath(file_path, '.')
                    zipf.write(file_path, arcname)
    
    print(f"✅ ZIP package created: {args.zip_name}")
    
    # Upload to GitLab artifacts S3 bucket
    try:
        s3_client = boto3.client('s3')
        bucket_name = os.getenv('GITLAB_ARTIFACTS_BUCKET')
        
        if bucket_name:
            key = f"releases/{args.release_type}/{args.zip_name}"
            s3_client.upload_file(args.zip_name, bucket_name, key)
            print(f"✅ Uploaded to S3: s3://{bucket_name}/{key}")
        else:
            print("⚠️ GITLAB_ARTIFACTS_BUCKET not set, skipping S3 upload")
            
    except Exception as e:
        print(f"⚠️ S3 upload failed: {e}")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
