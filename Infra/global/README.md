# Global Infrastructure

This directory holds infrastructure that is shared across `dev` and `prod`.

## Purpose

The first shared resource is the CircleCI deploy IAM user used by `.circleci/config.yml`.

It can:
- read, write, and delete deployment artifacts in the buckets configured in local tfvars
- create CloudFront invalidations for the deployed distributions

## Apply

This is a separate Terraform root from `../`.

```bash
cd infra/global
terraform init
terraform apply
```

Copy `terraform.tfvars.example` to local `terraform.tfvars` before applying. The
checked-in values are documentation placeholders. Keep real backend settings in
ignored `backend.hcl` and initialize with:

```bash
terraform init -backend-config=backend.hcl
```

## CircleCI Outputs

After apply, copy these values into CircleCI:

```bash
terraform output -raw circleci_aws_access_key_id
terraform output -raw circleci_aws_secret_access_key
```

- `circleci_aws_access_key_id` -> `AWS_ACCESS_KEY_ID`
- `circleci_aws_secret_access_key` -> `AWS_SECRET_ACCESS_KEY`
- `aws_region` from local `terraform.tfvars` -> `TASKTRACE_AWS_REGION`

The generated IAM user is only for deployment. Its policy is scoped to the S3
buckets and CloudFront distribution IDs configured in local `terraform.tfvars`.
