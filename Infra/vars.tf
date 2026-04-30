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

variable "loadbalancer_cert_arn" {
  type = string
}

variable "tasktrace_cert_arn" {
  type = string
}

variable "root_bucket" {
  type = string
}

variable "tasktrace_url" {
  type = string
}

variable "tasktrace_route53_zone_id" {
  type = string
}

variable "tasktrace_dev_waf_ipv4_allowlist" {
  type = list(string)
}

locals {
  account_id            = var.aws_account_id
  loadbalancer_cert_arn = var.loadbalancer_cert_arn
  tasktrace_cert_arn    = var.tasktrace_cert_arn

  public_subnet_a_cidr      = "10.0.1.0/24"
  public_subnet_b_cidr      = "10.0.2.0/24"
  public_subnet_c_cidr      = "10.0.3.0/24"
  private_subnet_a_cidr     = "10.0.4.0/24"
  private_subnet_b_cidr     = "10.0.5.0/24"
  private_subnet_c_cidr     = "10.0.6.0/24"
  root_bucket               = var.root_bucket
  auth_url_prefix           = "auth${terraform.workspace}"
  ecs_server_container_name = "tasktrace-server-container-${terraform.workspace}"

  tasktrace_url                    = var.tasktrace_url
  tasktrace_auth_url               = "${local.auth_url_prefix}.${local.tasktrace_url}"
  tasktrace_prefixed_url           = "${terraform.workspace}.${local.tasktrace_url}"
  www_tasktrace_url                = "www.${local.tasktrace_url}"
  tasktrace_static_site_url        = terraform.workspace == "prod" ? local.tasktrace_url : local.tasktrace_prefixed_url
  tasktrace_server_url             = terraform.workspace == "prod" ? "api.${local.tasktrace_url}" : "apidev.${local.tasktrace_url}"
  tasktrace_route53_zone_id        = var.tasktrace_route53_zone_id
  tasktrace_dev_waf_ipv4_allowlist = var.tasktrace_dev_waf_ipv4_allowlist
}
