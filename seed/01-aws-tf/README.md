# k0s on AWS with Cilium CNI

Terraform configuration to deploy a production-ready k0s Kubernetes cluster on AWS with:
- **k0s** v1.33.4+k0s.0 (Default CNI kuberouter disabled)
- **Cilium** v1.18.2 as CNI
- **AWS Cloud Controller Manager** v0.0.9
- **AWS EBS CSI Driver** v2.49.0
- **Network Load Balancer** for HA API access
- **IMDSv2** security disable by default (issue with CCM pod not able to retrieve EC2 information from metadata server, would need to work on IAM permissions)

## Architecture

- 3 controller nodes (controller+worker role)
- 2 worker nodes
- Single subnet deployment
- Network Load Balancer with dedicated ports:
  - 6443: Kubernetes API
  - 443: HTTPS
  - 9443: k0s API
  - 8132: Konnectivity

## Prerequisites

1. **Terraform** >= 0.14.3 brew tap hashicorp/tap && brew install hashicorp/tap/terraform
2. **k0sctl** CLI installed  brew install k0sproject/tap/k0sctl
3. **kubectl** CLI installed  brew install kubectl
4. **helm** CLI  installed brew install helm
5. **AWS Credentials** - Export your AWS credentials:

```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_SESSION_TOKEN="your-session-token"  # If using temporary credentials
```

5. **IAM Roles** - Ensure the following IAM instance profiles exist in your AWS account:
   - `k8s-cluster-contoller-role` (for controllers)(type is normal here...)
   - `k8s-worker-policy` (for workers)

### Required IAM Policies

#### Controller Node Policy
The controller IAM role should have the AWS Cloud Provider policy permissions (EC2 full access for demo purposes, or restrict as needed).

#### Worker Node Policy
Add the following inline policy to `k8s-worker-policy`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "K8sWorkerNodePermissions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ec2:DescribeVolumes",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    }
  ]
}
```

## Configuration

Customize your deployment by editing [terraform.tfvars](terraform.tfvars):

```hcl
# Cluster Configuration
cluster_name     = "k0s-cilium-cluster"
controller_count = 3
worker_count     = 2
cluster_flavor   = "m5.large"

# Network Configuration
aws_region        = "us-west-1"
vpc_cidr_block    = "172.20.0.0/16"
subnet_cidr_block = "172.20.0.0/24"
availability_zone = "us-west-1b"

# AMI Configuration
ubuntu_ami_filter = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"

# IAM Configuration
controller_iam_instance_profile = "k8s-cluster-contoller-role"
worker_iam_instance_profile     = "k8s-worker-policy"

# Storage Configuration
root_volume_size = 50

# k0s and Helm Chart Versions
k0s_version                  = "1.33.4+k0s.0"
cilium_version               = "1.18.2"
aws_cloud_controller_version = "0.0.9"
aws_ebs_csi_driver_version   = "2.49.0"

# Security Configuration
imdsv2_required = false  # Enforce IMDSv2 for enhanced security
```

See [variables.tf](variables.tf) for all available configuration options.

## Deployment

### 1. Initialize Terraform

```bash
terraform init -lock=false
```

### 2. Review the Plan

```bash
terraform plan -lock=false
```

### 3. Apply the Configuration

```bash
terraform apply -auto-approve -lock=false
```

### 4. Deploy k0s Cluster

```bash
terraform output -raw k0s_cluster | k0sctl apply --no-wait --debug --config -
```

### 5. Get Kubeconfig

```bash
terraform output -raw k0s_cluster | k0sctl kubeconfig --config -
```

### 6. Apply Storage Class (Optional)

```bash
kubectl --kubeconfig kubeconfig apply -f storageclass.yaml
```

## Verification

```bash
# Set kubeconfig
export KUBECONFIG=./kubeconfig

# Check nodes
kubectl get nodes

# Check Cilium status
kubectl -n kube-system get pods -l app.kubernetes.io/name=cilium

# Check AWS Cloud Controller Manager
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-cloud-controller-manager

# Check EBS CSI Driver
kubectl -n kube-system get pods -l app=ebs-csi-controller
```

## Accessing the Cluster

The Kubernetes API is accessible via the Network Load Balancer:

```bash
terraform output k8s_api_lb_dns
```

## Cleanup

To destroy all resources:

```bash
terraform destroy -auto-approve -lock=false
```

**Note:** Ensure all Kubernetes resources (LoadBalancers, PVCs) are deleted before destroying the cluster to avoid orphaned AWS resources.

## Security Considerations

- **IMDSv2**: Enabled by default to protect against SSRF attacks
- **Security Groups**: Currently allow `0.0.0.0/0` for demo purposes. Restrict to specific IPs in production:
  - Edit [main.tf](main.tf) lines 85, 93, 101 to limit access
- **SSH Key**: Private key saved to `aws_private.pem` in the module directory

## Troubleshooting

### SSH Access to Nodes

```bash
ssh -i aws_private.pem ubuntu@<node-public-ip>
```

### View k0s Logs

```bash
journalctl -u k0scontroller  # On controller nodes
journalctl -u k0sworker      # On worker nodes
```

### Check Cloud Provider Integration

```bash
kubectl describe nodes | grep "ProviderID"
```

## Architecture Details

- **Load Balancer**: Network Load Balancer (NLB) with static EIP
- **Networking**: Cilium CNI with custom pod CIDR (10.244.0.0/16)
- **Proxy Mode**: IPVS with strict ARP enabled (for MetalLB compatibility)
- **Storage**: etcd for cluster state, EBS CSI for persistent volumes
- **Worker Profile**: Custom configuration with 220 max pods per node

## Files

- [main.tf](main.tf) - Core infrastructure and k0s configuration
- [controller.tf](controller.tf) - Controller node definitions
- [worker.tf](worker.tf) - Worker node definitions
- [variables.tf](variables.tf) - Variable definitions
- [terraform.tfvars](terraform.tfvars) - Variable values
- [storageclass.yaml](storageclass.yaml) - Optional storage class definition
