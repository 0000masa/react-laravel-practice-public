module "app" {
  source = "../modules/app-infrastructure"

  project_name             = var.project_name
  github_repository        = var.github_repository
  github_environment_name  = var.github_environment_name
  tfstate_bucket           = var.tfstate_bucket
  tfstate_key              = var.tfstate_key
  domain_name              = var.domain_name
  sub_frontend_domain_name = var.sub_frontend_domain_name
  sub_backend_domain_name  = var.sub_backend_domain_name
  db_name                  = var.db_name
  db_username              = var.db_username
  parameter_store_path     = var.parameter_store_path
  image_tag_nginx          = var.image_tag_nginx
  image_tag_laravel        = var.image_tag_laravel
  ecr_repo_name_nginx      = var.ecr_repo_name_nginx
  ecr_repo_name_laravel    = var.ecr_repo_name_laravel
  enable_nat_gateway       = var.enable_nat_gateway
  app_env                  = var.app_env

  rds_config = var.rds_config

  ecs_web_service_config             = var.ecs_web_service_config
  ecs_queue_worker_service_config    = var.ecs_queue_worker_service_config
  ecs_runner_task_config             = var.ecs_runner_task_config
  ecs_batch_daily_report_task_config = var.ecs_batch_daily_report_task_config

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
