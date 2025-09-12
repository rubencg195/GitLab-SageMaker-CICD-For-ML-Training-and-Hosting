# EBS Volume for GitLab data
resource "aws_ebs_volume" "gitlab_data" {
  availability_zone = aws_subnet.private_subnets[0].availability_zone
  size              = local.gitlab_volume_size
  type              = local.gitlab_volume_type
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-gitlab-data"
  })
}

# GitLab EC2 Instance (Public)
resource "aws_instance" "gitlab_server" {
  ami                    = local.ubuntu_ami_id
  instance_type          = local.gitlab_instance_type
  key_name               = aws_key_pair.gitlab_key.key_name
  vpc_security_group_ids = [aws_security_group.gitlab_sg.id]
  subnet_id              = aws_subnet.public_subnets[0].id
  iam_instance_profile   = aws_iam_instance_profile.gitlab_profile.name
  associate_public_ip_address = true

  root_block_device {
    volume_type = local.root_volume_type
    volume_size = local.root_volume_size
    encrypted   = true
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
# Bootstrap script to run the full GitLab installation
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting GitLab installation bootstrap at $(date)"

# Create directory for scripts
mkdir -p /opt/gitlab-scripts

# The actual installation will be handled by the Terraform remote-exec provisioner
echo "Bootstrap completed at $(date)"
EOF
  )

  tags = local.gitlab_tags

  # Copy the full installation script and execute it
  provisioner "file" {
    source      = "server-scripts/gitlab-install.sh"
    destination = "/tmp/gitlab-install.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /opt/gitlab-scripts",
      "sudo mv /tmp/gitlab-install.sh /opt/gitlab-scripts/gitlab-install.sh",
      "sudo chmod +x /opt/gitlab-scripts/gitlab-install.sh",
      "sudo /opt/gitlab-scripts/gitlab-install.sh"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }
}

# Attach EBS volume to GitLab instance
resource "aws_volume_attachment" "gitlab_data_attachment" {
  device_name = local.ebs_device_name
  volume_id   = aws_ebs_volume.gitlab_data.id
  instance_id = aws_instance.gitlab_server.id
}

# Elastic IP for GitLab server
resource "aws_eip" "gitlab_eip" {
  instance = aws_instance.gitlab_server.id
  domain   = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-gitlab-eip"
  })

  depends_on = [aws_internet_gateway.gitlab_igw]
}
