variable "project_id" {
  type = string
}

variable "project_name" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-northeast1"
}

variable "app_env" {
  type    = string
  default = "staging"
}

variable "domain_name" {
  type = string
}

variable "image_domain_name" {
  type = string
}

variable "dns_managed_zone_dns_name" {
  type = string
}

variable "db_name" {
  type    = string
  default = "practice_db"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "github_repository" {
  type = string
}

variable "image_tag_nginx" {
  type = string
}

variable "image_tag_laravel" {
  type = string
}

variable "cloudsql_config" {
  type = object({
    tier                = string
    availability_type   = string
    disk_size           = number
    backup_enabled      = bool
    deletion_protection = bool
  })
}

variable "cloud_run_config" {
  type = object({
    cpu           = string
    memory        = string
    min_instances = number
    max_instances = number
  })
}
