provider "aws" {
  region = var.region
  default_tags { tags = local.tags }
}

locals {
  tags = {
    Project     = "baktrack"
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source          = "../../modules/vpc"
  name_prefix     = var.cluster_name
  vpc_cidr        = var.vpc_cidr
  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  cluster_name    = var.cluster_name
  tags            = local.tags
}

module "eks" {
  source             = "../../modules/eks"
  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  tags               = local.tags
}

module "ecr" {
  source           = "../../modules/ecr"
  repository_names = var.ecr_repositories
  tags             = local.tags
}