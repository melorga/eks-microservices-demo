# Remote state. Bucket / table must exist out-of-band (chicken-and-egg).
# TODO: replace with your bucket / table names before `terraform init`.
terraform {
  backend "s3" {
    bucket         = "REPLACE-ME-tfstate-bucket" # TODO: replace with your bucket
    key            = "eks-microservices-demo/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE-ME-tfstate-lock" # TODO: replace with your table
    encrypt        = true
  }
}
