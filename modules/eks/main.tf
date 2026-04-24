module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.13"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access = true   # we need to reach it from our laptop
  enable_irsa                    = true

  # Addons managed by EKS itself (not Helm)
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
  }

  eks_managed_node_groups = {
    system = {
      name           = "system"
      instance_types = ["t3.micro"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      labels         = { role = "system" }
      taints         = [{ key = "CriticalAddonsOnly", value = "true", effect = "NO_SCHEDULE" }]
    }
    app = {
      name           = "app"
      instance_types = ["t3.micro"]
      capacity_type  = "ON_DEMAND"   # using ON_DEMAND — spot t3.micro unfulfillable in ap-south-1
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      labels         = { role = "app" }
    }
  }

  # Tag subnets for Karpenter discovery
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}