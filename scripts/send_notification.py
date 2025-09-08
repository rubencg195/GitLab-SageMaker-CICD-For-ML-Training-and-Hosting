#!/usr/bin/env python3
"""
Send Notification Script for GitLab CI/CD Pipeline
This script sends notifications about pipeline status to various channels.
"""

import argparse
import json
import logging
import os
import requests
import sys
from datetime import datetime
from typing import Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class NotificationSender:
    def __init__(self):
        """Initialize the notification sender."""
        self.pipeline_info = self._get_pipeline_info()
        
    def _get_pipeline_info(self) -> Dict[str, Any]:
        """Get pipeline information from environment variables."""
        return {
            'project_name': os.environ.get('CI_PROJECT_NAME', 'Unknown Project'),
            'project_url': os.environ.get('CI_PROJECT_URL', ''),
            'pipeline_id': os.environ.get('CI_PIPELINE_ID', 'unknown'),
            'pipeline_url': os.environ.get('CI_PIPELINE_URL', ''),
            'pipeline_status': os.environ.get('CI_PIPELINE_STATUS', 'unknown'),
            'commit_sha': os.environ.get('CI_COMMIT_SHA', 'unknown'),
            'commit_short_sha': os.environ.get('CI_COMMIT_SHORT_SHA', 'unknown'),
            'commit_ref_name': os.environ.get('CI_COMMIT_REF_NAME', 'unknown'),
            'commit_message': os.environ.get('CI_COMMIT_MESSAGE', 'No commit message'),
            'commit_author': os.environ.get('CI_COMMIT_AUTHOR', 'Unknown Author'),
            'job_name': os.environ.get('CI_JOB_NAME', 'unknown'),
            'job_stage': os.environ.get('CI_JOB_STAGE', 'unknown'),
            'job_url': os.environ.get('CI_JOB_URL', ''),
            'runner_description': os.environ.get('CI_RUNNER_DESCRIPTION', 'unknown'),
            'timestamp': datetime.now().isoformat(),
            'merge_request_iid': os.environ.get('CI_MERGE_REQUEST_IID', ''),
            'merge_request_title': os.environ.get('CI_MERGE_REQUEST_TITLE', ''),
        }
    
    def _get_status_emoji(self, status: str) -> str:
        """Get emoji for pipeline status."""
        status_emojis = {
            'success': '✅',
            'failed': '❌',
            'canceled': '⚠️',
            'skipped': '⏭️',
            'running': '🔄',
            'pending': '⏳',
            'unknown': '❓'
        }
        return status_emojis.get(status.lower(), '❓')
    
    def _get_status_color(self, status: str) -> str:
        """Get color for pipeline status."""
        status_colors = {
            'success': '#28a745',  # Green
            'failed': '#dc3545',   # Red
            'canceled': '#ffc107', # Yellow
            'skipped': '#6c757d',  # Gray
            'running': '#007bff',  # Blue
            'pending': '#17a2b8',  # Teal
            'unknown': '#6c757d'   # Gray
        }
        return status_colors.get(status.lower(), '#6c757d')
    
    def send_slack_notification(self, webhook_url: str) -> bool:
        """Send notification to Slack."""
        try:
            info = self.pipeline_info
            status_emoji = self._get_status_emoji(info['pipeline_status'])
            color = self._get_status_color(info['pipeline_status'])
            
            # Build message
            message = {
                "attachments": [
                    {
                        "color": color,
                        "title": f"{status_emoji} Pipeline {info['pipeline_status'].title()}",
                        "title_link": info['pipeline_url'],
                        "fields": [
                            {
                                "title": "Project",
                                "value": f"<{info['project_url']}|{info['project_name']}>",
                                "short": True
                            },
                            {
                                "title": "Branch",
                                "value": info['commit_ref_name'],
                                "short": True
                            },
                            {
                                "title": "Commit",
                                "value": f"`{info['commit_short_sha']}` by {info['commit_author']}",
                                "short": True
                            },
                            {
                                "title": "Pipeline ID",
                                "value": f"<{info['pipeline_url']}|#{info['pipeline_id']}>",
                                "short": True
                            }
                        ],
                        "footer": "GitLab CI/CD",
                        "ts": int(datetime.now().timestamp())
                    }
                ]
            }
            
            # Add commit message if available
            if info['commit_message'] and info['commit_message'] != 'No commit message':
                message["attachments"][0]["fields"].append({
                    "title": "Commit Message",
                    "value": info['commit_message'][:200] + ('...' if len(info['commit_message']) > 200 else ''),
                    "short": False
                })
            
            # Add merge request info if available
            if info['merge_request_iid']:
                message["attachments"][0]["fields"].append({
                    "title": "Merge Request",
                    "value": f"!{info['merge_request_iid']} - {info['merge_request_title']}",
                    "short": False
                })
            
            # Send notification
            response = requests.post(webhook_url, json=message, timeout=10)
            response.raise_for_status()
            
            logger.info("Slack notification sent successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send Slack notification: {e}")
            return False
    
    def send_teams_notification(self, webhook_url: str) -> bool:
        """Send notification to Microsoft Teams."""
        try:
            info = self.pipeline_info
            status_emoji = self._get_status_emoji(info['pipeline_status'])
            color = self._get_status_color(info['pipeline_status'])
            
            # Build message
            message = {
                "@type": "MessageCard",
                "@context": "https://schema.org/extensions",
                "summary": f"Pipeline {info['pipeline_status']} - {info['project_name']}",
                "themeColor": color.replace('#', ''),
                "title": f"{status_emoji} Pipeline {info['pipeline_status'].title()}",
                "sections": [
                    {
                        "activityTitle": info['project_name'],
                        "activitySubtitle": f"Branch: {info['commit_ref_name']}",
                        "facts": [
                            {
                                "name": "Commit",
                                "value": f"{info['commit_short_sha']} by {info['commit_author']}"
                            },
                            {
                                "name": "Pipeline ID",
                                "value": info['pipeline_id']
                            },
                            {
                                "name": "Status",
                                "value": info['pipeline_status'].title()
                            },
                            {
                                "name": "Timestamp",
                                "value": info['timestamp']
                            }
                        ]
                    }
                ],
                "potentialAction": [
                    {
                        "@type": "OpenUri",
                        "name": "View Pipeline",
                        "targets": [
                            {
                                "os": "default",
                                "uri": info['pipeline_url']
                            }
                        ]
                    },
                    {
                        "@type": "OpenUri",
                        "name": "View Project",
                        "targets": [
                            {
                                "os": "default",
                                "uri": info['project_url']
                            }
                        ]
                    }
                ]
            }
            
            # Add commit message if available
            if info['commit_message'] and info['commit_message'] != 'No commit message':
                message["sections"][0]["facts"].append({
                    "name": "Commit Message",
                    "value": info['commit_message'][:200] + ('...' if len(info['commit_message']) > 200 else '')
                })
            
            # Send notification
            response = requests.post(webhook_url, json=message, timeout=10)
            response.raise_for_status()
            
            logger.info("Teams notification sent successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send Teams notification: {e}")
            return False
    
    def send_discord_notification(self, webhook_url: str) -> bool:
        """Send notification to Discord."""
        try:
            info = self.pipeline_info
            status_emoji = self._get_status_emoji(info['pipeline_status'])
            color = int(self._get_status_color(info['pipeline_status']).replace('#', ''), 16)
            
            # Build embed
            embed = {
                "title": f"{status_emoji} Pipeline {info['pipeline_status'].title()}",
                "url": info['pipeline_url'],
                "color": color,
                "fields": [
                    {
                        "name": "Project",
                        "value": f"[{info['project_name']}]({info['project_url']})",
                        "inline": True
                    },
                    {
                        "name": "Branch",
                        "value": info['commit_ref_name'],
                        "inline": True
                    },
                    {
                        "name": "Commit",
                        "value": f"`{info['commit_short_sha']}` by {info['commit_author']}",
                        "inline": True
                    },
                    {
                        "name": "Pipeline ID",
                        "value": f"[#{info['pipeline_id']}]({info['pipeline_url']})",
                        "inline": True
                    }
                ],
                "footer": {
                    "text": "GitLab CI/CD"
                },
                "timestamp": info['timestamp']
            }
            
            # Add commit message if available
            if info['commit_message'] and info['commit_message'] != 'No commit message':
                embed["fields"].append({
                    "name": "Commit Message",
                    "value": info['commit_message'][:200] + ('...' if len(info['commit_message']) > 200 else ''),
                    "inline": False
                })
            
            message = {"embeds": [embed]}
            
            # Send notification
            response = requests.post(webhook_url, json=message, timeout=10)
            response.raise_for_status()
            
            logger.info("Discord notification sent successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send Discord notification: {e}")
            return False
    
    def send_email_notification(self, ses_region: str, sender_email: str, recipient_emails: list) -> bool:
        """Send email notification using AWS SES."""
        try:
            import boto3
            from botocore.exceptions import ClientError
            
            info = self.pipeline_info
            status_emoji = self._get_status_emoji(info['pipeline_status'])
            
            # Create SES client
            ses_client = boto3.client('ses', region_name=ses_region)
            
            # Build email content
            subject = f"{status_emoji} Pipeline {info['pipeline_status'].title()} - {info['project_name']}"
            
            html_body = f"""
            <html>
            <head></head>
            <body>
                <h2>{status_emoji} Pipeline {info['pipeline_status'].title()}</h2>
                <p><strong>Project:</strong> <a href="{info['project_url']}">{info['project_name']}</a></p>
                <p><strong>Branch:</strong> {info['commit_ref_name']}</p>
                <p><strong>Commit:</strong> {info['commit_short_sha']} by {info['commit_author']}</p>
                <p><strong>Pipeline ID:</strong> <a href="{info['pipeline_url']}">#{info['pipeline_id']}</a></p>
                <p><strong>Status:</strong> {info['pipeline_status'].title()}</p>
                <p><strong>Timestamp:</strong> {info['timestamp']}</p>
                
                {f'<p><strong>Commit Message:</strong> {info["commit_message"]}</p>' if info['commit_message'] != 'No commit message' else ''}
                {f'<p><strong>Merge Request:</strong> !{info["merge_request_iid"]} - {info["merge_request_title"]}</p>' if info['merge_request_iid'] else ''}
                
                <p><a href="{info['pipeline_url']}">View Pipeline</a> | <a href="{info['project_url']}">View Project</a></p>
            </body>
            </html>
            """
            
            text_body = f"""
            Pipeline {info['pipeline_status'].title()} - {info['project_name']}
            
            Project: {info['project_name']}
            Branch: {info['commit_ref_name']}
            Commit: {info['commit_short_sha']} by {info['commit_author']}
            Pipeline ID: #{info['pipeline_id']}
            Status: {info['pipeline_status'].title()}
            Timestamp: {info['timestamp']}
            
            {f'Commit Message: {info["commit_message"]}' if info['commit_message'] != 'No commit message' else ''}
            {f'Merge Request: !{info["merge_request_iid"]} - {info["merge_request_title"]}' if info['merge_request_iid'] else ''}
            
            Pipeline URL: {info['pipeline_url']}
            Project URL: {info['project_url']}
            """
            
            # Send email
            response = ses_client.send_email(
                Source=sender_email,
                Destination={'ToAddresses': recipient_emails},
                Message={
                    'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                    'Body': {
                        'Text': {'Data': text_body, 'Charset': 'UTF-8'},
                        'Html': {'Data': html_body, 'Charset': 'UTF-8'}
                    }
                }
            )
            
            logger.info(f"Email notification sent successfully (MessageId: {response['MessageId']})")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send email notification: {e}")
            return False
    
    def save_notification_log(self) -> None:
        """Save notification log for debugging."""
        try:
            log_data = {
                'timestamp': self.pipeline_info['timestamp'],
                'pipeline_info': self.pipeline_info,
                'notification_sent': True
            }
            
            with open('notification_log.json', 'w') as f:
                json.dump(log_data, f, indent=2)
                
            logger.info("Notification log saved")
            
        except Exception as e:
            logger.error(f"Failed to save notification log: {e}")

def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Send CI/CD pipeline notifications')
    parser.add_argument('--pipeline-status', default=os.environ.get('CI_PIPELINE_STATUS', 'unknown'),
                       help='Pipeline status')
    parser.add_argument('--project-name', default=os.environ.get('CI_PROJECT_NAME', 'Unknown Project'),
                       help='Project name')
    parser.add_argument('--pipeline-url', default=os.environ.get('CI_PIPELINE_URL', ''),
                       help='Pipeline URL')
    parser.add_argument('--slack-webhook', 
                       help='Slack webhook URL')
    parser.add_argument('--teams-webhook',
                       help='Microsoft Teams webhook URL')
    parser.add_argument('--discord-webhook',
                       help='Discord webhook URL')
    parser.add_argument('--email-sender',
                       help='Email sender address (for SES)')
    parser.add_argument('--email-recipients', nargs='+',
                       help='Email recipient addresses')
    parser.add_argument('--ses-region', default='us-east-1',
                       help='AWS SES region')
    
    args = parser.parse_args()
    
    try:
        # Initialize notification sender
        notifier = NotificationSender()
        
        # Track success
        success_count = 0
        total_attempts = 0
        
        # Send Slack notification
        if args.slack_webhook:
            total_attempts += 1
            if notifier.send_slack_notification(args.slack_webhook):
                success_count += 1
        
        # Send Teams notification
        if args.teams_webhook:
            total_attempts += 1
            if notifier.send_teams_notification(args.teams_webhook):
                success_count += 1
        
        # Send Discord notification
        if args.discord_webhook:
            total_attempts += 1
            if notifier.send_discord_notification(args.discord_webhook):
                success_count += 1
        
        # Send email notification
        if args.email_sender and args.email_recipients:
            total_attempts += 1
            if notifier.send_email_notification(args.ses_region, args.email_sender, args.email_recipients):
                success_count += 1
        
        # Save notification log
        notifier.save_notification_log()
        
        # Report results
        if total_attempts == 0:
            logger.warning("No notification channels configured")
        else:
            logger.info(f"Notifications sent: {success_count}/{total_attempts}")
            
        if success_count < total_attempts:
            logger.warning("Some notifications failed to send")
            sys.exit(1)
        else:
            logger.info("All notifications sent successfully")
        
    except Exception as e:
        logger.error(f"FAILED: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
