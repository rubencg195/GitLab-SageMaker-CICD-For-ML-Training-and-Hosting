#!/bin/bash

# GitLab Health Check Script (Bash Version)
# Optimized for ~10 minute GitLab deployment window with 12 retries
# This script replaces the Python version for better reliability during startup

# Configuration
DEFAULT_GITLAB_IP=""
RETRY_COUNT=12
RETRY_INTERVAL=50  # 50 seconds between retries = ~10 minutes total
SSH_USER="ubuntu"
SSH_KEY="$HOME/.ssh/id_rsa"  # Fixed path expansion
LOG_FILE=".out/gitlab_health_check_$(date +%Y%m%d_%H%M%S).log"
VERBOSE=false

# Simple output functions without colors
print_info() {
    echo "INFO: $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo "SUCCESS: $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo "WARNING: $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo "ERROR: $1" | tee -a "$LOG_FILE"
}

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "GitLab Health Check Script with 12 retries (~10 minutes)"
    echo ""
    echo "Options:"
    echo "  --gitlab-ip IP    GitLab server IP (auto-detected if not provided)"
    echo "  --retries COUNT   Number of retries (default: 12)"
    echo "  --interval SEC    Seconds between retries (default: 50)"
    echo "  --ssh-user USER   SSH username (default: ubuntu)"
    echo "  --verbose         Enable verbose output"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                 # Auto-detect IP, use defaults"
    echo "  $0 --gitlab-ip 1.2.3.4           # Use specific IP"
    echo "  $0 --retries 15 --interval 40     # Custom timing"
    echo "  $0 --verbose                      # Show detailed output"
}

# Function to auto-detect GitLab IP from OpenTofu
detect_gitlab_ip() {
    # Send log messages to stderr to avoid contaminating the return value
    echo "Auto-detecting GitLab IP from OpenTofu outputs..." >&2
    
    if command -v tofu >/dev/null 2>&1; then
        local ip=$(tofu output -raw gitlab_public_ip 2>/dev/null)
        if [ ! -z "$ip" ] && [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"  # Only the IP goes to stdout
            return 0
        fi
    fi
    
    echo "ERROR: Failed to auto-detect GitLab IP. Please specify with --gitlab-ip" >&2
    return 1
}

# Function to check HTTP connectivity
check_http_connectivity() {
    local ip=$1
    local url="http://$ip"
    
    if [ "$VERBOSE" = true ]; then
        print_info "Checking HTTP connectivity to $url"
    fi
    
    local response=$(curl -s -I --connect-timeout 15 --max-time 20 "$url" 2>/dev/null | head -1)
    
    if [[ "$response" == *"200"* ]] || [[ "$response" == *"302"* ]]; then
        if [ "$VERBOSE" = true ]; then
            print_success "HTTP connectivity: $response"
        fi
        return 0
    else
        if [ "$VERBOSE" = true ]; then
            print_warning "HTTP not ready: $response"
        fi
        return 1
    fi
}

# Function to check SSH connectivity
check_ssh_connectivity() {
    local ip=$1
    
    if [ "$VERBOSE" = true ]; then
        print_info "Checking SSH connectivity to $ip"
    fi
    
    # Simplified SSH check
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=10 "$SSH_USER@$ip" "echo 'SSH OK'" >/dev/null 2>&1; then
        if [ "$VERBOSE" = true ]; then
            print_success "SSH connectivity working"
        fi
        return 0
    else
        if [ "$VERBOSE" = true ]; then
            print_warning "SSH not ready"
        fi
        return 1
    fi
}

# Function to check GitLab services
check_gitlab_services() {
    local ip=$1
    
    if [ "$VERBOSE" = true ]; then
        print_info "Checking GitLab services status"
    fi
    
    # Simplified services check - just check if gitlab-ctl status works and returns running services
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=10 "$SSH_USER@$ip" "sudo gitlab-ctl status | grep -q 'run:'" >/dev/null 2>&1; then
        if [ "$VERBOSE" = true ]; then
            print_success "GitLab services running"
        fi
        return 0
    else
        if [ "$VERBOSE" = true ]; then
            print_warning "GitLab services not ready"
        fi
        return 1
    fi
}

# Function to check GitLab web interface
check_web_interface() {
    local ip=$1
    local signin_url="http://$ip/users/sign_in"
    
    if [ "$VERBOSE" = true ]; then
        print_info "Checking GitLab web interface"
    fi
    
    local response=$(curl -s --connect-timeout 15 --max-time 20 "$signin_url" 2>/dev/null)
    
    if [[ "$response" == *"GitLab"* ]] || [[ "$response" == *"sign_in"* ]] || [[ "$response" == *"Sign in"* ]]; then
        if [ "$VERBOSE" = true ]; then
            print_success "GitLab web interface accessible"
        fi
        return 0
    else
        if [ "$VERBOSE" = true ]; then
            print_warning "GitLab web interface not ready"
        fi
        return 1
    fi
}

# Function to get root password
get_root_password() {
    local ip=$1
    
    if [ "$VERBOSE" = true ]; then
        print_info "Retrieving GitLab root password"
    fi
    
    # Simplified password retrieval
    local password=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                    -o ConnectTimeout=10 "$SSH_USER@$ip" \
                    "sudo cat /etc/gitlab/initial_root_password | grep 'Password:' | awk '{print \$2}'" 2>/dev/null)
    
    if [ ! -z "$password" ] && [ "$password" != "Password:" ]; then
        echo "$password"
        return 0
    else
        return 1
    fi
}

# Function to perform comprehensive health check
perform_health_check() {
    local ip=$1
    local attempt=$2
    
    log_with_timestamp "=== HEALTH CHECK ATTEMPT $attempt/$RETRY_COUNT ==="
    log_with_timestamp "Checking GitLab at $ip..."
    
    # Step 1: Check HTTP connectivity
    if ! check_http_connectivity "$ip"; then
        log_with_timestamp "❌ HTTP connectivity failed"
        return 1
    fi
    
    # Step 2: Check SSH connectivity
    if ! check_ssh_connectivity "$ip"; then
        log_with_timestamp "❌ SSH connectivity failed"
        return 1
    fi
    
    # Step 3: Check GitLab services
    if ! check_gitlab_services "$ip"; then
        log_with_timestamp "❌ GitLab services not ready"
        return 1
    fi
    
    # Step 4: Check web interface
    if ! check_web_interface "$ip"; then
        log_with_timestamp "❌ GitLab web interface not ready"
        return 1
    fi
    
    # Step 5: Get root password
    local root_password=$(get_root_password "$ip")
    if [ -z "$root_password" ]; then
        log_with_timestamp "❌ Root password not available yet"
        return 1
    fi
    
    # All checks passed!
    log_with_timestamp "🎉 ALL HEALTH CHECKS PASSED!"
    log_with_timestamp "✅ GitLab is fully operational"
    log_with_timestamp "🌐 URL: http://$ip"
    log_with_timestamp "👤 Username: root"
    log_with_timestamp "🔑 Password: $root_password"
    
    return 0
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --gitlab-ip)
                DEFAULT_GITLAB_IP="$2"
                shift 2
                ;;
            --retries)
                RETRY_COUNT="$2"
                shift 2
                ;;
            --interval)
                RETRY_INTERVAL="$2"
                shift 2
                ;;
            --ssh-user)
                SSH_USER="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Create .out directory if it doesn't exist
    mkdir -p .out
    
    # Start logging
    log_with_timestamp "========================================="
    log_with_timestamp "GitLab Health Check Script (Bash Version)"
    log_with_timestamp "Started: $(date)"
    log_with_timestamp "========================================="
    
    # Get GitLab IP
    local gitlab_ip="$DEFAULT_GITLAB_IP"
    if [ -z "$gitlab_ip" ]; then
        gitlab_ip=$(detect_gitlab_ip)
        if [ $? -ne 0 ]; then
            exit 1
        fi
    fi
    
    print_success "GitLab IP detected: $gitlab_ip"
    log_with_timestamp "Configuration: $RETRY_COUNT retries, ${RETRY_INTERVAL}s intervals (~$((RETRY_COUNT * RETRY_INTERVAL / 60)) minutes total)"
    log_with_timestamp ""
    
    # Health check retry loop
    for ((attempt=1; attempt<=RETRY_COUNT; attempt++)); do
        if perform_health_check "$gitlab_ip" "$attempt"; then
            print_success "🎉 GitLab is ready and fully operational!"
            log_with_timestamp "Health check completed successfully after $((attempt * RETRY_INTERVAL - RETRY_INTERVAL)) seconds"
            exit 0
        fi
        
        if [ $attempt -lt $RETRY_COUNT ]; then
            log_with_timestamp "⏳ Attempt $attempt failed. Waiting ${RETRY_INTERVAL}s before retry..."
            print_info "Waiting ${RETRY_INTERVAL} seconds... (Attempt $attempt/$RETRY_COUNT)"
            sleep "$RETRY_INTERVAL"
        fi
    done
    
    # All retries exhausted
    log_with_timestamp "⏰ All $RETRY_COUNT attempts completed"
    log_with_timestamp "GitLab may still be initializing. Manual check recommended:"
    log_with_timestamp "- Check: curl -I http://$gitlab_ip"
    log_with_timestamp "- SSH: ssh -i $SSH_KEY $SSH_USER@$gitlab_ip"
    log_with_timestamp "- Services: ssh $SSH_USER@$gitlab_ip 'sudo gitlab-ctl status'"
    
    print_warning "Health check timeout after $((RETRY_COUNT * RETRY_INTERVAL / 60)) minutes"
    print_info "Log file: $LOG_FILE"
    
    exit 1
}

# Run main function with all arguments
main "$@"
