output "cluster_name"     { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "region"           { value = var.region }
output "ecr_urls"         { value = module.ecr.repository_urls }
output "kubeconfig_cmd"   {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
output "vpc_id" { value = module.vpc.vpc_id }