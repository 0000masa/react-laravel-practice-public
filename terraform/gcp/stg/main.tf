module "app" {
  source = "../modules/app-infrastructure"

  project_id   = var.project_id
  project_name = var.project_name
  region       = var.region
  app_env      = var.app_env

  domain_name               = var.domain_name
  image_domain_name         = var.image_domain_name
  dns_managed_zone_dns_name = var.dns_managed_zone_dns_name

  db_name     = var.db_name
  db_username = var.db_username

  github_repository = var.github_repository

  image_tag_nginx   = var.image_tag_nginx
  image_tag_laravel = var.image_tag_laravel

  cloudsql_config  = var.cloudsql_config
  cloud_run_config = var.cloud_run_config

  providers = {
    google      = google
    google-beta = google-beta
    random      = random
  }
}

output "lb_ip_address" {
  value = module.app.lb_ip_address
}

output "dns_name_servers" {
  value = module.app.dns_name_servers
}

output "cloudsql_connection_name" {
  value = module.app.cloudsql_connection_name
}

output "cloud_run_uri" {
  value = module.app.cloud_run_uri
}

output "artifact_registry_host" {
  value = module.app.artifact_registry_host
}

output "wif_provider" {
  value = module.app.wif_provider
}

output "gha_push_service_accounts" {
  value = module.app.gha_push_service_accounts
}

output "run_deploy_service_account" {
  value = module.app.run_deploy_service_account
}
