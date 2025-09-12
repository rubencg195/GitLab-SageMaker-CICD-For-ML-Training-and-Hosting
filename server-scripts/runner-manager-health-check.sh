#!/bin/bash
# Health check for GitLab Runner Manager

echo "=== GitLab Runner Manager Health Check ==="
echo "Date: $(date)"
echo ""

echo "Runner Status:"
gitlab-runner status

echo ""
echo "Runner List:"
gitlab-runner list

echo ""
echo "Docker Machine List:"
docker-machine ls 2>/dev/null || echo "No machines found"

echo ""
echo "System Resources:"
echo "CPU Usage: $(top -bn1 | grep \"%Cpu(s)\" | awk '{print $2}' | cut -d'%' -f1)%"
echo "Memory Usage: $(free -m | awk 'NR==2{printf \"%.1f%%\", $3*100/$2}')"
echo "Disk Usage: $(df -h / | awk 'NR==2{printf \"%s\", $5}')"

echo ""
echo "=== Health Check Complete ==="
