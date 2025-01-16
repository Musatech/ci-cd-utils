variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "stg", "hml", "prd"], var.environment)
    error_message = "Valid values for var: environment are (dev, stg, hml, prd)."
  }
}

variable "project-name" {
  type = string
}

variable "team" {
  type = string
}

variable "app-domain" {
  type = string
}

variable "dns-domain" {
  type     = string
  nullable = true
}

variable "acm-certificate-domain" {
  type = string
}

locals {
  ####
  ## app settings configuration
  ####
  project_name   = var.project-name
  bucket_name    = "${local.project_name}-front-${local.environment_short}"
  request_policy = "read-discover" // see available_request_methods in this file
  cache_policy   = "read-discover" // see available_cache_methods in this file

  ####
  ## deploy vars - not edit
  ####
  environment_short  = var.environment
  environment        = lookup(local.environment_map, local.environment_short)
  acm_domain         = var.acm-certificate-domain
  domain             = var.app-domain
  domain_dns         = var.dns-domain
  ttl_times          = lookup(local.available_ttl, local.environment_short)
  allowed_methods    = lookup(local.available_request_methods, local.request_policy)
  s3_allowed_methods = [for x in local.allowed_methods : x if !contains(["OPTIONS", "PATCH"], x)]
  cache_methods      = lookup(local.available_cache_methods, local.cache_policy)

  ####
  ## mapping options - not edit
  ####
  environment_map = {
    "dev" = "development"
    "stg" = "staging"
    "hml" = "homolog"
    "prd" = "production"
  }

  available_ttl = {
    "dev" = { "min_ttl" = 0, "default_ttl" = 10, "max_ttl" = 20 }
    "stg" = { "min_ttl" = 0, "default_ttl" = 10, "max_ttl" = 20 }
    "hml" = { "min_ttl" = 1800, "default_ttl" = 3600, "max_ttl" = 86400 }
    "prd" = { "min_ttl" = 1800, "default_ttl" = 3600, "max_ttl" = 86400 }
  }

  available_request_methods = {
    "read-only"     = ["GET", "HEAD"]
    "read-discover" = ["GET", "HEAD", "OPTIONS"]
    "allow-all"     = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
  }

  available_cache_methods = {
    "read-only"     = ["GET", "HEAD"]
    "read-discover" = ["GET", "HEAD", "OPTIONS"]
  }

  common_tags = {
    Environment = var.environment
    Team        = var.team
    Service     = var.project-name
    Name        = "${var.project-name}.service.${var.environment}.musa.co"
  }
}
