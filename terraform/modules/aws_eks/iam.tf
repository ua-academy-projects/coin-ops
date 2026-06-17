# iam.tf — two separate IAM roles, kept apart on purpose:
#
#   1. Cluster role  — assumed by the EKS service itself (the control plane).
#      AWS uses this internally to manage ENIs in your VPC, write logs, etc.
#      You never "use" this role directly — EKS does, behind the scenes.
#
#   2. Node role      — attached to worker EC2 instances via an instance
#      profile, the exact same mechanism used for the CloudWatch Agent role
#      on the k3s nodes in the monitoring task. Lets each worker node join
#      the cluster, pull container images, and manage pod networking (CNI).

# ── Cluster role (control plane) ────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.cluster_name}-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── Node role (worker EC2 instances) ────────────────────────────────────

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.cluster_name}-node-role" }
}

# Three managed policies required for a working EKS worker node:
#   - AmazonEKSWorkerNodePolicy        — lets the node register with the cluster
#   - AmazonEKS_CNI_Policy             — lets the node manage pod networking (CNI)
#   - AmazonEC2ContainerRegistryReadOnly — lets the node pull container images
resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
