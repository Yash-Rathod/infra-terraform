variable "region" {
  type    = string
  default = "ap-south-1"
}
variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for TF state. Example: baktrack-tfstate-<account-id>"
}
variable "lock_table_name" {
  type    = string
  default = "baktrack-tf-lock"
}