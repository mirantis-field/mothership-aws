terraform {
  required_version = ">= 0.14.3"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "cluster_vpc" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "cluster_igw" {
  vpc_id = aws_vpc.cluster_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "cluster_subnet" {
  vpc_id                  = aws_vpc.cluster_vpc.id
  cidr_block              = var.subnet_cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-subnet"
  }
}

# Route Table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cluster_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster_igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# Associate route table with public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.cluster_subnet.id
  route_table_id = aws_route_table.public.id
}

resource "tls_private_key" "k0sctl" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "cluster-key" {
  key_name   = format("%s_key", var.cluster_name)
  public_key = tls_private_key.k0sctl.public_key_openssh
}

// Save the private key to filesystem
resource "local_file" "aws_private_pem" {
  file_permission = "600"
  filename        = format("%s/%s", path.module, "aws_private.pem")
  content         = tls_private_key.k0sctl.private_key_pem
}

resource "aws_security_group" "cluster_allow_ssh" {
  name        = format("%s-allow-ssh", var.cluster_name)
  description = "Allow ssh inbound traffic"
  vpc_id      = aws_vpc.cluster_vpc.id

  # SSH Access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to your IP for security: "123.45.67.89/32"
  }

  ingress {
    description = "All TCP"
    from_port   = 1
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to your IP for security: "123.45.67.89/32"
  }

  ingress {
    description = "All UDP"
    from_port   = 1
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = format("%s-allow-ssh", var.cluster_name)
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ubuntu_ami_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ubuntu_ami_owner]
}

# Elastic IP for NLB
resource "aws_eip" "nlb" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nlb-eip"
  }
}

# Network Load Balancer for API server
resource "aws_lb" "k8s_api" {
  name               = "${var.cluster_name}-k8s-api-lb"
  internal           = false
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id     = aws_subnet.cluster_subnet.id
    allocation_id = aws_eip.nlb.id
  }

  enable_deletion_protection = false

  tags = {
    Name = "${var.cluster_name}-k8s-api-lb"
  }
}

# Target group for port 6443
resource "aws_lb_target_group" "k8s_api" {
  name     = "${var.cluster_name}-k8s-api-tg"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.cluster_vpc.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "6443"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = {
    Name = "${var.cluster_name}-k8s-api-tg"
  }
}

# Listener for port 6443
resource "aws_lb_listener" "k8s_api" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_api.arn
  }
}

# Attach controller instances to target group
resource "aws_lb_target_group_attachment" "k8s_api_controllers" {
  count            = length(aws_instance.cluster-controller)
  target_group_arn = aws_lb_target_group.k8s_api.arn
  target_id        = aws_instance.cluster-controller[count.index].id
  port             = 6443
}

# Target group for port 443
resource "aws_lb_target_group" "https" {
  name     = "${var.cluster_name}-https-tg"
  port     = 443
  protocol = "TCP"
  vpc_id   = aws_vpc.cluster_vpc.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "443"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = {
    Name = "${var.cluster_name}-https-tg"
  }
}

# Listener for port 443
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

# Attach controller instances to port 443 target group
resource "aws_lb_target_group_attachment" "https_controllers" {
  count            = length(aws_instance.cluster-controller)
  target_group_arn = aws_lb_target_group.https.arn
  target_id        = aws_instance.cluster-controller[count.index].id
  port             = 443
}

# Target group for port 9443
resource "aws_lb_target_group" "k0s_api" {
  name     = "${var.cluster_name}-k0s-api-tg"
  port     = 9443
  protocol = "TCP"
  vpc_id   = aws_vpc.cluster_vpc.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "9443"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = {
    Name = "${var.cluster_name}-k0s-api-tg"
  }
}

# Listener for port 9443
resource "aws_lb_listener" "k0s_api" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = "9443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k0s_api.arn
  }
}

# Attach controller instances to port 9443 target group
resource "aws_lb_target_group_attachment" "k0s_api_controllers" {
  count            = length(aws_instance.cluster-controller)
  target_group_arn = aws_lb_target_group.k0s_api.arn
  target_id        = aws_instance.cluster-controller[count.index].id
  port             = 9443
}

# Target group for port 8132
resource "aws_lb_target_group" "konnectivity" {
  name     = "${var.cluster_name}-konnectivity-tg"
  port     = 8132
  protocol = "TCP"
  vpc_id   = aws_vpc.cluster_vpc.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "8132"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = {
    Name = "${var.cluster_name}-konnectivity-tg"
  }
}

# Listener for port 8132
resource "aws_lb_listener" "konnectivity" {
  load_balancer_arn = aws_lb.k8s_api.arn
  port              = "8132"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.konnectivity.arn
  }
}

# Attach controller instances to port 8132 target group
resource "aws_lb_target_group_attachment" "konnectivity_controllers" {
  count            = length(aws_instance.cluster-controller)
  target_group_arn = aws_lb_target_group.konnectivity.arn
  target_id        = aws_instance.cluster-controller[count.index].id
  port             = 8132
}

locals {
  k0s_tmpl = {
    apiVersion = "k0sctl.k0sproject.io/v1beta1"
    kind       = "cluster"
    spec = {
      hosts = concat(
        [for host in aws_instance.cluster-controller : {
          ssh = {
            address = host.public_ip
            user    = "ubuntu"
            keyPath = "./aws_private.pem"
          }
          installFlags = [
            "--disable-components=endpoint-reconciler",
            "--enable-cloud-provider",
            "--kubelet-extra-args=\"--cloud-provider=external\"",
            "--profile=worker-config",
            "--logging kube-apiserver=0,kube-controller-manager=0,kube-scheduler=0,kubelet=0,etcd=error,containerd=error,konnectivity-server=0"
          ]
          role = host.tags["Role"]
        }],
        [for host in aws_instance.cluster-workers : {
          ssh = {
            address = host.public_ip
            user    = "ubuntu"
            keyPath = "./aws_private.pem"
          }
          installFlags = [
            "--enable-cloud-provider",
            "--kubelet-extra-args=\"--cloud-provider=external\""
          ]
          role = host.tags["Role"]
        }]
      )
      k0s = {
        version       = var.k0s_version
        dynamicConfig = false
        config = {
          apiVersion = "k0s.k0sproject.io/v1beta1"
          kind       = "Cluster"
          metadata = {
            name = "${var.cluster_name}"
          }
          spec = {
            api = {
              address         = aws_eip.nlb.public_ip
              externalAddress = aws_lb.k8s_api.dns_name
              k0sApiPort      = 9443
              port            = 6443
              sans = concat([
                aws_eip.nlb.public_ip,
                aws_lb.k8s_api.dns_name
              ], [for instance in aws_instance.cluster-controller : instance.public_ip])
              tunneledNetworkingMode = false
            }
            controllerManager = {}
            installConfig = {
              users = {
                etcdUser          = "etcd"
                kineUser          = "kube-apiserver"
                konnectivityUser  = "konnectivity-server"
                kubeAPIserverUser = "kube-apiserver"
                kubeSchedulerUser = "kube-scheduler"
              }
            }
            network = {
              nodeLocalLoadBalancing = {
                enabled = false
                type    = "EnvoyProxy"
              }
              kubeProxy = {
                disabled = false
                mode     = "ipvs"
                ipvs = {
                  strictARP = true
                }
              }
              podCIDR = "10.244.0.0/16"
              #custom means that podCIDR is ignored. As cilium is deployed as helm, the default Cilium podCIDR is used: 10.0.0.0/8
              provider    = "custom"
              serviceCIDR = "10.96.0.0/12"
            }
            workerProfiles = [
              {
                name = "worker-config"
                values = {
                  containerLogMaxSize  = "1Mi"
                  containerLogMaxFiles = 2
                  maxPods              = 220
                }
              }
            ]
            storage = {
              type = "etcd"
            }
            telemetry = {
              enabled = true
            }
            extensions = {
              helm = {
                repositories = [
                  {
                    name = "cilium"
                    url  = "https://helm.cilium.io/"
                  },
                  {
                    name = "aws-cloud-controller-manager"
                    url  = "https://kubernetes.github.io/cloud-provider-aws"
                  },
                  {
                    name = "aws-ebs-csi-driver"
                    url  = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
                  }
                ]
                charts = [
                  {
                    name      = "a-cilium"
                    chartname = "cilium/cilium"
                    namespace = "kube-system"
                    version   = var.cilium_version
                  },
                  {
                    name      = "b-aws-cloud-controller-manager"
                    chartname = "aws-cloud-controller-manager/aws-cloud-controller-manager"
                    namespace = "kube-system"
                    version   = var.aws_cloud_controller_version
                    values    = <<-EOT
                      args:
                        - --v=2
                        - --cloud-provider=aws
                        - --allocate-node-cidrs=false
                        - --cluster-cidr=${var.subnet_cidr_block}
                        - --cluster-name=${var.cluster_name}
                      nodeSelector:
                        node-role.kubernetes.io/control-plane: "true"
                    EOT
                  },
                  {
                    name      = "c-aws-ebs-csi-driver"
                    chartname = "aws-ebs-csi-driver/aws-ebs-csi-driver"
                    namespace = "kube-system"
                    version   = var.aws_ebs_csi_driver_version
                    values    = <<-EOT
                      node:
                        kubeletPath: /var/lib/k0s/kubelet
                    EOT
                  }
                ]
              }
            }
          }
        }
      }
    }
  }
}

output "k0s_cluster" {
  value = replace(yamlencode(local.k0s_tmpl), "/((?:^|\n)[\\s-]*)\"([\\w-]+)\":/", "$1$2:")
}

output "k8s_api_lb_dns" {
  value       = aws_lb.k8s_api.dns_name
  description = "DNS name of the Kubernetes API load balancer"
}
