terraform {
  backend "s3" {
    bucket         = "baktrack-tfstate-347486023960"
    key            = "envs/prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "baktrack-tf-lock"
    encrypt        = true
  }
  required_version = ">= 1.8"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.50" }
  }
}