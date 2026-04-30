terraform {
  required_version = "1.14.7"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.24.0"
    }

  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
