variable "cluster_name" {
  type    = string
  default = "k0s-ds-cluster"
}

variable "controller_count" {
  type    = number
  default = 3
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "cluster_flavor" {
  type    = string
  default = "m5.xlarge"
}

variable "aws_region" {
  type        = string
  description = "AWS region for the cluster"
  default     = "us-west-1"
}

variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "172.20.0.0/16"
}

variable "subnet_cidr_block" {
  type        = string
  description = "CIDR block for the subnet"
  default     = "172.20.0.0/24"
}

variable "availability_zone" {
  type        = string
  description = "AWS availability zone for the subnet"
  default     = "us-west-1a"
}

variable "ubuntu_ami_filter" {
  type        = string
  description = "AMI filter for Ubuntu images"
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
}

variable "controller_iam_instance_profile" {
  type        = string
  description = "IAM instance profile for controller nodes"
  default     = "k8s-cluster-contoller-role"
}

variable "worker_iam_instance_profile" {
  type        = string
  description = "IAM instance profile for worker nodes"
  default     = "k8s-worker-policy"
}

variable "root_volume_size" {
  type        = number
  description = "Root volume size in GB for instances"
  default     = 50
}

variable "k0s_version" {
  type        = string
  description = "k0s version to install"
  default     = "1.33.4+k0s.0"
}

variable "cilium_version" {
  type        = string
  description = "Cilium Helm chart version"
  default     = "1.18.2"
}

variable "aws_cloud_controller_version" {
  type        = string
  description = "AWS Cloud Controller Manager Helm chart version"
  default     = "0.0.9"
}

variable "aws_ebs_csi_driver_version" {
  type        = string
  description = "AWS EBS CSI Driver Helm chart version"
  default     = "2.49.0"
}

variable "imdsv2_required" {
  type        = bool
  description = "Require IMDSv2 for instance metadata"
  default     = true
}

variable "ubuntu_ami_owner" {
  type        = string
  description = "AWS account ID that owns the Ubuntu AMI"
  default     = "099720109477"
}
