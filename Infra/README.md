# Infrastructure

## Workspaces
There are two workspaces:
* dev
* prod
do not use the default workspace.

Copy `terraform.tfvars.example` to local `terraform.tfvars` and fill in the AWS
account, certificate, Route 53, domain, and WAF allowlist values for your own
deployment. The S3 backend is intentionally partial in checked-in Terraform;
keep real backend settings in ignored `backend.hcl` and initialize with:

```bash
terraform init -backend-config=backend.hcl
```
