terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "vpc_eks" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "sub_eks" {
  count = 2

  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.vpc_eks.id
}

resource "aws_internet_gateway" "ig_eks" {
  vpc_id = aws_vpc.vpc_eks.id
}

resource "aws_route" "rt_eks" {
  route_table_id         = aws_vpc.vpc_eks.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig_eks.id
}

resource "aws_iam_role" "iam_role_eks" {
  name = "terraform_demo_role_eks"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_eks_cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.iam_role_eks.name
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_eks_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.iam_role_eks.name
}

resource "aws_security_group" "sg_eks" {
  name   = "sg_eks"
  vpc_id = aws_vpc.vpc_eks.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "sgr_eks" {
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.sg_eks.id
  to_port           = 443
  type              = "ingress"
}

resource "aws_eks_cluster" "eks_demo" {
  name     = "eks_demo"
  role_arn = aws_iam_role.iam_role_eks.arn

  vpc_config {
    security_group_ids = [aws_security_group.sg_eks.id]
    subnet_ids         = aws_subnet.sub_eks[*].id
  }

  depends_on = [
    aws_iam_role_policy_attachment.iam_role_policy_eks_cluster,
    aws_iam_role_policy_attachment.iam_role_policy_eks_controller
  ]
}

resource "aws_iam_role" "iam_role_ec2_eks" {
  name = "iam_role_ec2_eks"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "iam_role_ec2_ebs" {
  name = "iam_role_ec2_ebs"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume",
        "ec2:CreateSnapshot",
        "ec2:CreateTags",
        "ec2:CreateVolume",
        "ec2:DeleteSnapshot",
        "ec2:DeleteTags",
        "ec2:DeleteVolume",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DetachVolume"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_eks_node" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.iam_role_ec2_eks.name
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_eks_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.iam_role_ec2_eks.name
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_eks_ec2_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.iam_role_ec2_eks.name
}

resource "aws_iam_role_policy_attachment" "iam_role_policy_eks_ebs" {
  policy_arn = aws_iam_policy.iam_role_ec2_ebs.arn
  role       = aws_iam_role.iam_role_ec2_eks.name
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_demo.name
  node_group_name = "demo"
  node_role_arn   = aws_iam_role.iam_role_ec2_eks.arn
  subnet_ids      = aws_subnet.sub_eks[*].id

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.iam_role_policy_eks_node,
    aws_iam_role_policy_attachment.iam_role_policy_eks_cni,
    aws_iam_role_policy_attachment.iam_role_policy_eks_ec2_registry,
    aws_iam_role_policy_attachment.iam_role_policy_eks_ebs
  ]
}

variable "addons" {
  type = list(object({
    name    = string
    version = string
  }))

  default = [
    {
      name    = "kube-proxy"
      version = "v1.29.0-eksbuild.3"
    },
    {
      name    = "vpc-cni"
      version = "v1.16.2-eksbuild.1"
    },
    {
      name    = "coredns"
      version = "v1.11.1-eksbuild.6"
    },
    {
      name    = "aws-ebs-csi-driver"
      version = "v1.27.0-eksbuild.1"
    }
  ]
}

resource "aws_eks_addon" "addons" {
  for_each                    = { for addon in var.addons : addon.name => addon }
  cluster_name                = aws_eks_cluster.eks_demo.id
  addon_name                  = each.value.name
  addon_version               = each.value.version
  resolve_conflicts_on_create = "OVERWRITE"
}
