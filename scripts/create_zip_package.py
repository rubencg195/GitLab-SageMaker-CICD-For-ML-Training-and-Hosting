#!/usr/bin/env python3
"""
Create zip packages for ML model releases
This script creates zip files containing training scripts, model artifacts, and deployment configs
"""

import argparse
import os
import sys
import zipfile
import json
import boto3
from datetime import datetime
from pathlib import Path


def create_zip_package(zip_name, release_type, pr_id=None, commit_id=None, 
                      endpoint_name=None, model_name=None, training_output_dir=None, project_type=None):
    """
    Create a zip package containing all necessary files for the release
    """
    print(f"Creating {release_type} zip package: {zip_name}")
    
    # Determine project type from manifest if not provided
    if not project_type:
        project_type = get_project_type_from_manifest()
    
    # Create zip file
    with zipfile.ZipFile(zip_name, 'w', zipfile.ZIP_DEFLATED) as zipf:
        
        # Add source code
        add_source_code(zipf)
        
        # Add project-specific files based on type
        if project_type == "training":
            add_training_files(zipf)
            if training_output_dir and os.path.exists(training_output_dir):
                add_model_artifacts(zipf, training_output_dir)
        elif project_type == "inference":
            add_inference_files(zipf)
            if endpoint_name:
                add_endpoint_configs(zipf, endpoint_name)
        else:
            # Default behavior for unknown project types
            add_training_files(zipf)
            if training_output_dir and os.path.exists(training_output_dir):
                add_model_artifacts(zipf, training_output_dir)
        
        # Add deployment configurations
        add_deployment_configs(zipf, endpoint_name, model_name)
        
        # Add documentation
        add_documentation(zipf, release_type, pr_id, commit_id, project_type)
        
        # Add metadata
        add_metadata(zipf, release_type, pr_id, commit_id, endpoint_name, model_name, project_type)
    
    print(f"Zip package created successfully: {zip_name}")
    return zip_name


def add_source_code(zipf):
    """Add source code files to the zip"""
    source_dirs = ['src/', 'scripts/', 'tests/']
    
    for source_dir in source_dirs:
        if os.path.exists(source_dir):
            for root, dirs, files in os.walk(source_dir):
                for file in files:
                    if file.endswith(('.py', '.yml', '.yaml', '.json', '.txt', '.md')):
                        file_path = os.path.join(root, file)
                        arc_path = os.path.relpath(file_path, '.')
                        zipf.write(file_path, arc_path)
                        print(f"Added: {arc_path}")


def add_training_files(zipf):
    """Add training-related files"""
    training_files = [
        '.gitlab-ci.yml',
        'requirements.txt',
        'Dockerfile',
        'README.md'
    ]
    
    for file in training_files:
        if os.path.exists(file):
            zipf.write(file, file)
            print(f"Added: {file}")


def add_model_artifacts(zipf, training_output_dir):
    """Add model artifacts from training output"""
    if not os.path.exists(training_output_dir):
        return
    
    for root, dirs, files in os.walk(training_output_dir):
        for file in files:
            file_path = os.path.join(root, file)
            arc_path = os.path.join('model_artifacts', os.path.relpath(file_path, training_output_dir))
            zipf.write(file_path, arc_path)
            print(f"Added model artifact: {arc_path}")


def add_deployment_configs(zipf, endpoint_name, model_name):
    """Add deployment configuration files"""
    deployment_config = {
        "endpoint_name": endpoint_name,
        "model_name": model_name,
        "deployment_timestamp": datetime.now().isoformat(),
        "instance_type": "ml.t2.medium",
        "initial_instance_count": 1,
        "max_instance_count": 2 if "candidate" in str(endpoint_name) else 10,
        "auto_scaling": "candidate" not in str(endpoint_name)
    }
    
    config_content = json.dumps(deployment_config, indent=2)
    zipf.writestr('deployment_config.json', config_content)
    print("Added: deployment_config.json")


def add_documentation(zipf, release_type, pr_id, commit_id):
    """Add documentation files"""
    doc_content = f"""
# {release_type.title()} Release Documentation

## Release Information
- **Type**: {release_type}
- **PR ID**: {pr_id or 'N/A'}
- **Commit ID**: {commit_id or 'N/A'}
- **Created**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}

## Contents
This zip package contains:
- Source code and training scripts
- Model artifacts and weights
- Deployment configurations
- Documentation and metadata

## Usage
1. Extract the zip file
2. Review the deployment_config.json for endpoint details
3. Use the training scripts to reproduce the model
4. Deploy using the provided configurations

## Support
For questions or issues, please refer to the project documentation or contact the development team.
"""
    
    zipf.writestr('RELEASE_NOTES.md', doc_content)
    print("Added: RELEASE_NOTES.md")


def get_project_type_from_manifest():
    """Get project type from manifest.json file"""
    manifest_path = "manifest.json"
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, 'r') as f:
                manifest = json.load(f)
                return manifest.get("project_type", "unknown")
        except Exception as e:
            print(f"Warning: Could not read manifest.json: {e}")
    return "unknown"


def add_inference_files(zipf):
    """Add inference-related files"""
    inference_files = [
        'inference_handler.py',
        'requirements.txt',
        'Dockerfile'
    ]
    
    for file in inference_files:
        if os.path.exists(file):
            zipf.write(file, file)
            print(f"Added: {file}")


def add_endpoint_configs(zipf, endpoint_name):
    """Add endpoint configuration files"""
    endpoint_config = {
        "endpoint_name": endpoint_name,
        "endpoint_config_timestamp": datetime.now().isoformat(),
        "instance_type": "ml.t2.medium",
        "initial_instance_count": 1,
        "max_instance_count": 10,
        "auto_scaling": True
    }
    
    config_content = json.dumps(endpoint_config, indent=2)
    zipf.writestr('endpoint_config.json', config_content)
    print("Added: endpoint_config.json")


def add_metadata(zipf, release_type, pr_id, commit_id, endpoint_name, model_name, project_type=None):
    """Add metadata file"""
    metadata = {
        "release_type": release_type,
        "project_type": project_type or "unknown",
        "pr_id": pr_id,
        "commit_id": commit_id,
        "endpoint_name": endpoint_name,
        "model_name": model_name,
        "created_at": datetime.now().isoformat(),
        "version": f"{release_type}-{commit_id or 'unknown'}-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
        "package_contents": get_package_contents(project_type)
    }
    
    metadata_content = json.dumps(metadata, indent=2)
    zipf.writestr('metadata.json', metadata_content)
    print("Added: metadata.json")


def get_package_contents(project_type):
    """Get package contents based on project type"""
    if project_type == "training":
        return [
            "Source code (src/, scripts/, tests/)",
            "Training scripts and configurations",
            "Model artifacts (if available)",
            "Deployment configurations",
            "Documentation and release notes"
        ]
    elif project_type == "inference":
        return [
            "Source code (src/, scripts/, tests/)",
            "Inference handler scripts",
            "Endpoint configurations",
            "Deployment configurations",
            "Documentation and release notes"
        ]
    else:
        return [
            "Source code (src/, scripts/, tests/)",
            "Project files and configurations",
            "Deployment configurations",
            "Documentation and release notes"
        ]


def main():
    parser = argparse.ArgumentParser(description='Create zip packages for ML model releases')
    parser.add_argument('--zip-name', required=True, help='Name of the zip file to create')
    parser.add_argument('--release-type', required=True, choices=['candidate', 'stable'], 
                       help='Type of release (candidate or stable)')
    parser.add_argument('--pr-id', help='Pull request ID')
    parser.add_argument('--commit-id', help='Commit ID')
    parser.add_argument('--endpoint-name', help='SageMaker endpoint name')
    parser.add_argument('--model-name', help='SageMaker model name')
    parser.add_argument('--training-output', help='Path to training output directory')
    parser.add_argument('--project-type', choices=['training', 'inference'], 
                       help='Project type (training or inference)')
    
    args = parser.parse_args()
    
    try:
        zip_file = create_zip_package(
            zip_name=args.zip_name,
            release_type=args.release_type,
            pr_id=args.pr_id,
            commit_id=args.commit_id,
            endpoint_name=args.endpoint_name,
            model_name=args.model_name,
            training_output_dir=args.training_output,
            project_type=args.project_type
        )
        
        # Get file size
        file_size = os.path.getsize(zip_file)
        print(f"Package created successfully: {zip_file} ({file_size:,} bytes)")
        
    except Exception as e:
        print(f"Error creating zip package: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
