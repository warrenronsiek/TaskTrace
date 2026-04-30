variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "aws_profile" {
  type    = string
  default = null
}

variable "aws_account_id" {
  type = string
}

variable "circleci_deploy_buckets" {
  type = list(string)
}

variable "circleci_deploy_distribution_ids" {
  type = list(string)
}

locals {
  account_id                       = var.aws_account_id
  circleci_deploy_buckets          = var.circleci_deploy_buckets
  circleci_deploy_distribution_ids = var.circleci_deploy_distribution_ids
}

resource "aws_iam_user" "circleci_deploy" {
  name = "tasktrace-circleci-deploy"
  path = "/service-users/"
}

data "aws_iam_policy_document" "circleci_deploy" {
  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      for bucket in local.circleci_deploy_buckets :
      "arn:aws:s3:::${bucket}"
    ]
  }

  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]

    resources = [
      for bucket in local.circleci_deploy_buckets :
      "arn:aws:s3:::${bucket}/*"
    ]
  }

  statement {
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetDistribution",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
    ]

    resources = [
      for distribution_id in local.circleci_deploy_distribution_ids :
      "arn:aws:cloudfront::${local.account_id}:distribution/${distribution_id}"
    ]
  }
}

resource "aws_iam_user_policy" "circleci_deploy" {
  name   = "tasktrace-circleci-deploy"
  user   = aws_iam_user.circleci_deploy.name
  policy = data.aws_iam_policy_document.circleci_deploy.json
}

resource "aws_iam_access_key" "circleci_deploy" {
  user = aws_iam_user.circleci_deploy.name
}

output "circleci_aws_access_key_id" {
  value = aws_iam_access_key.circleci_deploy.id
}

output "circleci_aws_secret_access_key" {
  value     = aws_iam_access_key.circleci_deploy.secret
  sensitive = true
}

output "circleci_aws_iam_user_name" {
  value = aws_iam_user.circleci_deploy.name
}
