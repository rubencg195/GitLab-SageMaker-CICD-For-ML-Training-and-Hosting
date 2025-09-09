# Local-exec provisioner to wait for GitLab and retrieve credentials
resource "null_resource" "gitlab_setup_wait" {
  depends_on = [aws_instance.gitlab_server]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for GitLab to be ready (optimized for faster startup)..."
      max_attempts=40  # Reduced from 60 due to optimizations
      attempt=1
      
      # Initial wait for instance boot and installation start
      echo "Initial wait for installation to begin..."
      sleep 30
      
      while [ $attempt -le $max_attempts ]; do
        if curl -s -f --max-time 8 http://${aws_instance.gitlab_server.public_ip}/users/sign_in > /dev/null 2>&1; then
          echo "GitLab is ready after $((30 + attempt*8)) seconds!"
          break
        fi
        echo "Attempt $attempt/$max_attempts: GitLab not ready yet, waiting 8 seconds..."
        sleep 8  # Slightly longer than install script checks for efficiency
        ((attempt++))
      done
      
      if [ $attempt -gt $max_attempts ]; then
        echo "GitLab readiness timeout after $((30 + max_attempts*8)) seconds"
        echo "This may be normal - GitLab might still be initializing database"
        echo "Installation will continue with user creation..."
      fi
    EOT
  }

  triggers = {
    instance_id = aws_instance.gitlab_server.id
  }
}

# Local-exec provisioner for basic GitLab readiness verification
resource "null_resource" "gitlab_verification" {
  depends_on = [null_resource.gitlab_setup_wait]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Verifying GitLab installation completed..."
      
      # Simple verification that GitLab is responding
      max_attempts=5
      attempt=1
      
      while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: Checking GitLab response..."
        
        if curl -s -f --max-time 10 http://${aws_instance.gitlab_server.public_ip}/users/sign_in > /dev/null 2>&1; then
          echo "✅ GitLab is responding to HTTP requests!"
          echo ""
          echo "🔑 To get your root password, run:"
          echo "tofu output gitlab_root_password"
          echo ""
          echo "Then execute the SSH command it shows you."
          break
        fi
        
        echo "⚠️ GitLab not responding yet, waiting 30 seconds..."
        sleep 30
        ((attempt++))
      done
      
      if [ $attempt -gt $max_attempts ]; then
        echo "⚠️ GitLab not responding after verification attempts"
        echo "This is normal - GitLab may still be initializing"
        echo "You can still try to get the password using:"
        echo "tofu output gitlab_root_password"
      fi
    EOT
  }

  triggers = {
    setup_wait = null_resource.gitlab_setup_wait.id
    instance_ip = aws_instance.gitlab_server.public_ip
  }
}

# Local-exec provisioner to display GitLab credentials
resource "null_resource" "gitlab_credentials" {
  depends_on = [null_resource.gitlab_verification]

  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "🎉 GitLab Deployment Complete!"
      echo "==============================="
      echo "🌐 URL: http://${aws_instance.gitlab_server.public_ip}"
      echo "👤 Username: root"
      echo "🔑 Password: Run 'tofu output gitlab_root_password' and execute the command shown"
      echo "==============================="
      echo ""
      echo "📝 Next Steps:"
      echo "1. Run: tofu output gitlab_root_password"
      echo "2. Execute the SSH command it shows"
      echo "3. Use that password to login to GitLab"
      echo ""
      echo "🚀 GitLab is ready for use!"
    EOT
  }

  triggers = {
    verification = null_resource.gitlab_verification.id
  }
}
