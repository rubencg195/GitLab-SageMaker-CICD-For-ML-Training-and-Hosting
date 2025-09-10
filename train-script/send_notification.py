#!/usr/bin/env python3

import argparse
import sys

def main():
    parser = argparse.ArgumentParser(description='Send Pipeline Notification')
    parser.add_argument('--pipeline-status', required=True, help='Pipeline status')
    parser.add_argument('--project-name', required=True, help='Project name')
    parser.add_argument('--pipeline-url', help='Pipeline URL')
    
    args = parser.parse_args()
    
    print(f"Sending notification for project: {args.project_name}")
    print(f"Pipeline status: {args.pipeline_status}")
    
    if args.pipeline_url:
        print(f"Pipeline URL: {args.pipeline_url}")
    
    # Mock notification
    print("✅ Notification sent successfully")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
