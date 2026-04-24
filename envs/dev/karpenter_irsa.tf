module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.13"

  cluster_name           = module.eks.cluster_name
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn
  create_node_iam_role   = true
  create_access_entry    = true
  create_pod_identity_association = true
  namespace                      = "karpenter"
  enable_v1_permissions          = true
}

output "karpenter_queue_name"          { value = module.karpenter.queue_name }
output "karpenter_iam_role_arn"        { value = module.karpenter.iam_role_arn }
output "karpenter_node_iam_role_name"  { value = module.karpenter.node_iam_role_name }
