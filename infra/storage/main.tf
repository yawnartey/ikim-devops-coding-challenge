terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

resource "aws_s3_bucket" "backups" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}
