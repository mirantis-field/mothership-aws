resource "aws_instance" "cluster-controller" {
  count         = var.controller_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.cluster_flavor

  subnet_id = aws_subnet.cluster_subnet.id
  tags = {
    Name                                        = "${var.cluster_name}-controller-${count.index + 1}"
    "Role"                                      = "controller+worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
  key_name                    = aws_key_pair.cluster-key.key_name
  vpc_security_group_ids      = [aws_security_group.cluster_allow_ssh.id]
  iam_instance_profile        = var.controller_iam_instance_profile
  associate_public_ip_address = true
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.imdsv2_required ? "required" : "optional"
    http_put_response_hop_limit = 2
  }

  user_data = <<EOF
#!/bin/bash
# Use full qualified private DNS name for the host name.  Kube wants it this way.
# Get IMDSv2 token
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
# Fetch hostname using IMDSv2
HOSTNAME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/hostname)
echo $HOSTNAME > /etc/hostname
sed -i "s|\(127\.0\..\.. *\)localhost|\1$HOSTNAME|" /etc/hosts
hostname $HOSTNAME
EOF

  lifecycle {
    ignore_changes = [ami]
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
  }
}