
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Define the Auto Scaling Group
resource "aws_autoscaling_group" "my_asg" {
  name = var.project
  launch_template {
    id      = aws_launch_template.my_launch_config.id
    version = aws_launch_template.my_launch_config.latest_version
  }
  vpc_zone_identifier = [for sn in aws_subnet.my_subnet : sn.id]
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
    }
  }
  depends_on = [null_resource.upload_lock]
}

# Define the launch configuration
resource "aws_launch_template" "my_launch_config" {
  name                                 = var.project
  image_id                             = data.aws_ami.latest.id
  instance_type                        = var.instance_type
  instance_initiated_shutdown_behavior = "terminate"
  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = true
    security_groups             = [aws_security_group.my_security_group.id]
  }
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_type           = var.volume_type
      volume_size           = var.volume_size
    }
  }
  user_data = base64encode(<<EOF
#!/bin/bash
# This forces a refresh when any of the scripts we use change:
# ${aws_s3_object.program.source_hash}
# ${aws_s3_object.auth_proxy.source_hash}
# ${aws_s3_object.systemd_unit.source_hash}
# ${aws_s3_object.systemd_unit_proxy.source_hash}
# ${aws_s3_object.config.source_hash}
set -euv
cd /root
pip3 install boto3
export AWS_DEFAULT_REGION="${data.aws_region.current.name}"
export AWS_REGION="${data.aws_region.current.name}"
echo AWS_DEFAULT_REGION="${data.aws_region.current.name}" >>/etc/environment
echo AWS_REGION="${data.aws_region.current.name}" >>/etc/environment
echo TABLE_NAME="${aws_dynamodb_table.password_table.name}" >>/etc/environment
aws s3 cp "s3://${aws_s3_object.program.bucket}${aws_s3_object.program.key}" .
aws s3 cp "s3://${aws_s3_object.auth_proxy.bucket}${aws_s3_object.auth_proxy.key}" .
aws s3 cp "s3://${aws_s3_object.systemd_unit.bucket}${aws_s3_object.systemd_unit.key}" .
aws s3 cp "s3://${aws_s3_object.systemd_unit_proxy.bucket}${aws_s3_object.systemd_unit_proxy.key}" .
aws s3 cp "s3://${aws_s3_object.config.bucket}${aws_s3_object.config.key}" .
mv "$(basename "${aws_s3_object.systemd_unit.key}")" /etc/systemd/system/
mv "$(basename "${aws_s3_object.systemd_unit_proxy.key}")" /etc/systemd/system/
chmod a+x "$(basename "${aws_s3_object.program.key}")"
chmod a+x "$(basename "${aws_s3_object.auth_proxy.key}")"
mkdir -p ./.aws-ses-pop3-server
mv "$(basename "${aws_s3_object.config.key}")" ./.aws-ses-pop3-server/config.yaml
systemctl daemon-reload
systemctl enable "$(basename "${aws_s3_object.systemd_unit_proxy.key}")"
systemctl start "$(basename "${aws_s3_object.systemd_unit_proxy.key}")"
systemctl enable "$(basename "${aws_s3_object.systemd_unit.key}")"
systemctl start "$(basename "${aws_s3_object.systemd_unit.key}")"
EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = var.project,
      Project = var.project,
    }
  }
  tag_specifications {
    resource_type = "volume"
    tags = {
      Name    = var.project,
      Project = var.project,
    }
  }
  tag_specifications {
    resource_type = "network-interface"
    tags = {
      Name    = var.project,
      Project = var.project,
    }
  }
  depends_on = [
    null_resource.upload_lock
  ]
}

#resource "aws_autoscaling_schedule" "replace_instance" {
#  autoscaling_group_name = aws_autoscaling_group.my_asg.name
#  scheduled_action_name = "replace_instance"
#  recurrence = "cron(0 12 * * 1)"
#  time_zone = "Pacific/Auckland"
#}
