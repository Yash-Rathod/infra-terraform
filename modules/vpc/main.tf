module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true   # COST: one NAT shared across AZs, saves ~$32/mo/AZ
  enable_dns_hostnames = true

  # Required for EKS to auto-discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                           = 1
    "kubernetes.io/cluster/${var.cluster_name}"        = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                  = 1
    "kubernetes.io/cluster/${var.cluster_name}"        = "shared"
    "karpenter.sh/discovery"                           = var.cluster_name
  }

  tags = var.tags
}