# main.tf — the EKS control plane and the managed node group.
#
# Unlike modules/aws_vm, which creates plain aws_instance resources and
# Ansible installs k3s on top, here Terraform creates two AWS-native
# resources and AWS itself runs the Kubernetes control plane:
#
#   aws_eks_cluster     — the control plane (etcd, kube-apiserver, scheduler).
#                          AWS-managed, you never SSH into this.
#   aws_eks_node_group  — the worker EC2 instances. AWS handles launching,
#                          joining them to the cluster, and replacing them
#                          on failure (similar role to k3s-server-2/3, but
#                          Terraform/AWS manage the lifecycle, not Ansible).

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = var.subnet_ids
    # endpoint_public_access stays true (default) so kubectl works from your
    # laptop or from CodeBuild without needing a VPN/bastion into the VPC —
    # same reasoning as why k3s-server-1 had a public IP for SSH access.
    endpoint_public_access = true
  }

  # The cluster role's policy attachment must exist before the cluster is
  # created, or AWS rejects the create call with a permissions error —
  # the same kind of ordering issue you hit with the CloudWatch Agent
  # IAM role needing to exist before the instance profile attached it.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = { Name = var.cluster_name }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Same ordering reasoning as the cluster role — the node role's policies
  # must be attached before AWS tries to launch instances under that role.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]

  tags = { Name = "${var.cluster_name}-node" }
}
