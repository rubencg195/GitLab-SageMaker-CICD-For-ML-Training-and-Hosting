#!/usr/bin/env python3
"""
GitLab Health Check Script
This script performs automated health checks on the GitLab server after deployment.
"""

import argparse
import json
import logging
import requests
import subprocess
import sys
import time
from datetime import datetime
from typing import Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class GitLabHealthChecker:
    def __init__(self, gitlab_ip: str, ssh_user: str = "ubuntu"):
        """Initialize the health checker."""
        self.gitlab_ip = gitlab_ip
        self.ssh_user = ssh_user
        self.gitlab_url = f"http://{gitlab_ip}"
        self.results = {
            'timestamp': datetime.now().isoformat(),
            'gitlab_ip': gitlab_ip,
            'checks': {},
            'overall_status': 'unknown'
        }
    
    def check_network_connectivity(self) -> bool:
        """Check if GitLab server is reachable via HTTP."""
        try:
            logger.info(f"🌐 Checking network connectivity to {self.gitlab_url}")
            
            response = requests.get(self.gitlab_url, timeout=10, allow_redirects=True)
            
            if response.status_code in [200, 302]:
                logger.info(f"✅ Network connectivity: OK (Status: {response.status_code})")
                self.results['checks']['network_connectivity'] = {
                    'status': 'pass',
                    'details': f"HTTP {response.status_code} response received",
                    'response_time': response.elapsed.total_seconds()
                }
                return True
            else:
                logger.warning(f"⚠️ Network connectivity: Unexpected status {response.status_code}")
                self.results['checks']['network_connectivity'] = {
                    'status': 'warning',
                    'details': f"HTTP {response.status_code} response received"
                }
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"❌ Network connectivity: Failed - {e}")
            self.results['checks']['network_connectivity'] = {
                'status': 'fail',
                'details': str(e)
            }
            return False
    
    def check_ssh_connectivity(self) -> bool:
        """Check SSH connectivity to GitLab server."""
        try:
            logger.info(f"🔐 Checking SSH connectivity to {self.gitlab_ip}")
            
            # Test SSH connection with timeout
            cmd = [
                'ssh', 
                '-i', '~/.ssh/id_rsa',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'UserKnownHostsFile=/dev/null',
                '-o', 'LogLevel=ERROR',
                '-o', 'ConnectTimeout=10',
                f'{self.ssh_user}@{self.gitlab_ip}',
                'echo "SSH connection successful"'
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            
            if result.returncode == 0:
                logger.info("✅ SSH connectivity: OK")
                self.results['checks']['ssh_connectivity'] = {
                    'status': 'pass',
                    'details': 'SSH connection successful'
                }
                return True
            else:
                logger.error(f"❌ SSH connectivity: Failed - {result.stderr}")
                self.results['checks']['ssh_connectivity'] = {
                    'status': 'fail',
                    'details': result.stderr
                }
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("❌ SSH connectivity: Timeout")
            self.results['checks']['ssh_connectivity'] = {
                'status': 'fail',
                'details': 'SSH connection timeout'
            }
            return False
        except Exception as e:
            logger.error(f"❌ SSH connectivity: Failed - {e}")
            self.results['checks']['ssh_connectivity'] = {
                'status': 'fail',
                'details': str(e)
            }
            return False
    
    def check_gitlab_services(self) -> bool:
        """Check GitLab services status."""
        try:
            logger.info("🔧 Checking GitLab services status")
            
            cmd = [
                'ssh',
                '-i', '~/.ssh/id_rsa',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'UserKnownHostsFile=/dev/null',
                '-o', 'LogLevel=ERROR',
                '-o', 'ConnectTimeout=10',
                f'{self.ssh_user}@{self.gitlab_ip}',
                'sudo gitlab-ctl status'
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                services_output = result.stdout
                running_services = []
                failed_services = []
                
                for line in services_output.split('\n'):
                    if 'run:' in line:
                        service = line.split(':')[0].strip()
                        running_services.append(service)
                    elif 'down:' in line or 'fail:' in line:
                        service = line.split(':')[0].strip()
                        failed_services.append(service)
                
                if failed_services:
                    logger.warning(f"⚠️ GitLab services: Some services failed - {failed_services}")
                    self.results['checks']['gitlab_services'] = {
                        'status': 'warning',
                        'details': f"Running: {len(running_services)}, Failed: {len(failed_services)}",
                        'running_services': running_services,
                        'failed_services': failed_services
                    }
                    return False
                else:
                    logger.info(f"✅ GitLab services: All services running ({len(running_services)} services)")
                    self.results['checks']['gitlab_services'] = {
                        'status': 'pass',
                        'details': f"All {len(running_services)} services running",
                        'running_services': running_services
                    }
                    return True
            else:
                logger.error(f"❌ GitLab services: Failed to check - {result.stderr}")
                self.results['checks']['gitlab_services'] = {
                    'status': 'fail',
                    'details': result.stderr
                }
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("❌ GitLab services: Timeout")
            self.results['checks']['gitlab_services'] = {
                'status': 'fail',
                'details': 'Command timeout'
            }
            return False
        except Exception as e:
            logger.error(f"❌ GitLab services: Failed - {e}")
            self.results['checks']['gitlab_services'] = {
                'status': 'fail',
                'details': str(e)
            }
            return False
    
    def check_gitlab_web_interface(self) -> bool:
        """Check if GitLab web interface is accessible."""
        try:
            logger.info("🌐 Checking GitLab web interface")
            
            # Check login page
            login_url = f"{self.gitlab_url}/users/sign_in"
            response = requests.get(login_url, timeout=15, allow_redirects=True)
            
            if response.status_code == 200 and 'GitLab' in response.text:
                logger.info("✅ GitLab web interface: Login page accessible")
                self.results['checks']['web_interface'] = {
                    'status': 'pass',
                    'details': 'Login page accessible',
                    'response_time': response.elapsed.total_seconds()
                }
                return True
            else:
                logger.warning(f"⚠️ GitLab web interface: Unexpected response (Status: {response.status_code})")
                self.results['checks']['web_interface'] = {
                    'status': 'warning',
                    'details': f"Status {response.status_code}, GitLab content check failed"
                }
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"❌ GitLab web interface: Failed - {e}")
            self.results['checks']['web_interface'] = {
                'status': 'fail',
                'details': str(e)
            }
            return False
    
    def check_external_url_configuration(self) -> bool:
        """Check if GitLab external URL is properly configured."""
        try:
            logger.info("⚙️ Checking GitLab external URL configuration")
            
            cmd = [
                'ssh',
                '-i', '~/.ssh/id_rsa',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'UserKnownHostsFile=/dev/null',
                '-o', 'LogLevel=ERROR',
                '-o', 'ConnectTimeout=10',
                f'{self.ssh_user}@{self.gitlab_ip}',
                'sudo grep "^external_url" /etc/gitlab/gitlab.rb'
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            
            if result.returncode == 0:
                external_url = result.stdout.strip()
                if self.gitlab_ip in external_url:
                    logger.info(f"✅ External URL configuration: Correct - {external_url}")
                    self.results['checks']['external_url'] = {
                        'status': 'pass',
                        'details': f"Configured: {external_url}"
                    }
                    return True
                else:
                    logger.warning(f"⚠️ External URL configuration: IP mismatch - {external_url}")
                    self.results['checks']['external_url'] = {
                        'status': 'warning',
                        'details': f"Configured: {external_url}, Expected IP: {self.gitlab_ip}"
                    }
                    return False
            else:
                logger.error(f"❌ External URL configuration: Failed to check - {result.stderr}")
                self.results['checks']['external_url'] = {
                    'status': 'fail',
                    'details': result.stderr
                }
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("❌ External URL configuration: Timeout")
            self.results['checks']['external_url'] = {
                'status': 'fail',
                'details': 'Command timeout'
            }
            return False
        except Exception as e:
            logger.error(f"❌ External URL configuration: Failed - {e}")
            self.results['checks']['external_url'] = {
                'status': 'fail',
                'details': str(e)
            }
            return False
    
    def check_system_resources(self) -> bool:
        """Check system resources (disk, memory)."""
        try:
            logger.info("💾 Checking system resources")
            
            # Check disk space
            cmd = [
                'ssh',
                '-i', '~/.ssh/id_rsa',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'UserKnownHostsFile=/dev/null',
                '-o', 'LogLevel=ERROR',
                '-o', 'ConnectTimeout=10',
                f'{self.ssh_user}@{self.gitlab_ip}',
                'df -h / && free -h'
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            
            if result.returncode == 0:
                output = result.stdout
                logger.info("✅ System resources: Retrieved successfully")
                self.results['checks']['system_resources'] = {
                    'status': 'pass',
                    'details': 'System resources retrieved',
                    'output': output.strip()
                }
                return True
            else:
                logger.error(f"❌ System resources: Failed - {result.stderr}")
                self.results['checks']['system_resources'] = {
                    'status': 'fail',
                    'details': result.stderr
                }
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("❌ System resources: Timeout")
            self.results['checks']['system_resources'] = {
                'status': 'fail',
                'details': 'Command timeout'
            }
            return False
        except Exception as e:
            logger.error(f"❌ System resources: Failed - {e}")
            self.results['checks']['system_resources'] = {
                'status': 'fail',
                'details': str(e)
            }
            return False
    
    def run_all_checks(self) -> Dict[str, Any]:
        """Run all health checks."""
        logger.info(f"🚀 Starting GitLab health checks for {self.gitlab_ip}")
        logger.info("=" * 60)
        
        checks = [
            ("Network Connectivity", self.check_network_connectivity),
            ("SSH Connectivity", self.check_ssh_connectivity),
            ("GitLab Services", self.check_gitlab_services),
            ("Web Interface", self.check_gitlab_web_interface),
            ("External URL Config", self.check_external_url_configuration),
            ("System Resources", self.check_system_resources)
        ]
        
        passed_checks = 0
        total_checks = len(checks)
        
        for check_name, check_func in checks:
            logger.info(f"\n🔍 Running: {check_name}")
            try:
                if check_func():
                    passed_checks += 1
            except Exception as e:
                logger.error(f"❌ {check_name} failed with exception: {e}")
        
        # Determine overall status
        if passed_checks == total_checks:
            self.results['overall_status'] = 'healthy'
            status_emoji = "✅"
            status_text = "HEALTHY"
        elif passed_checks >= total_checks * 0.7:  # 70% pass rate
            self.results['overall_status'] = 'warning'
            status_emoji = "⚠️"
            status_text = "WARNING"
        else:
            self.results['overall_status'] = 'unhealthy'
            status_emoji = "❌"
            status_text = "UNHEALTHY"
        
        self.results['summary'] = {
            'passed_checks': passed_checks,
            'total_checks': total_checks,
            'pass_rate': round((passed_checks / total_checks) * 100, 2)
        }
        
        # Print summary
        logger.info("\n" + "=" * 60)
        logger.info(f"🏁 HEALTH CHECK SUMMARY")
        logger.info("=" * 60)
        logger.info(f"{status_emoji} Overall Status: {status_text}")
        logger.info(f"📊 Checks Passed: {passed_checks}/{total_checks} ({self.results['summary']['pass_rate']}%)")
        logger.info(f"🌐 GitLab URL: {self.gitlab_url}")
        
        return self.results
    
    def save_results(self, output_file: str = ".out/gitlab_health_check.json"):
        """Save results to JSON file."""
        try:
            # Ensure .out directory exists
            import os
            os.makedirs('.out', exist_ok=True)
            
            with open(output_file, 'w') as f:
                json.dump(self.results, f, indent=2)
            logger.info(f"📄 Results saved to: {output_file}")
        except Exception as e:
            logger.error(f"❌ Failed to save results: {e}")

def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Check GitLab server health')
    parser.add_argument('--gitlab-ip', 
                       help='GitLab server IP address (auto-detected if not provided)')
    parser.add_argument('--ssh-user', default='ubuntu',
                       help='SSH username (default: ubuntu)')
    parser.add_argument('--output-file', default='.out/gitlab_health_check.json',
                       help='Output file for results')
    parser.add_argument('--no-save', action='store_true',
                       help='Do not save results to file')
    
    args = parser.parse_args()
    
    try:
        # Auto-detect GitLab IP if not provided
        gitlab_ip = args.gitlab_ip
        if not gitlab_ip:
            logger.info("🔍 Auto-detecting GitLab IP from OpenTofu outputs...")
            try:
                result = subprocess.run(['tofu', 'output', '-raw', 'gitlab_public_ip'], 
                                      capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    gitlab_ip = result.stdout.strip()
                    logger.info(f"✅ Detected GitLab IP: {gitlab_ip}")
                else:
                    logger.error("❌ Failed to detect GitLab IP from OpenTofu outputs")
                    sys.exit(1)
            except Exception as e:
                logger.error(f"❌ Failed to detect GitLab IP: {e}")
                sys.exit(1)
        
        # Initialize health checker
        health_checker = GitLabHealthChecker(gitlab_ip, args.ssh_user)
        
        # Run all checks
        results = health_checker.run_all_checks()
        
        # Save results
        if not args.no_save:
            health_checker.save_results(args.output_file)
        
        # Exit with appropriate code
        if results['overall_status'] == 'healthy':
            logger.info("🎉 All checks passed! GitLab is healthy and ready to use.")
            sys.exit(0)
        elif results['overall_status'] == 'warning':
            logger.warning("⚠️ Some checks failed, but GitLab appears to be functional.")
            sys.exit(1)
        else:
            logger.error("❌ Multiple checks failed. GitLab may not be fully functional.")
            sys.exit(2)
        
    except KeyboardInterrupt:
        logger.info("🛑 Health check interrupted by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"❌ Health check failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
