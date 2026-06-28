project_name             = "practice-stg"
github_repository        = "0000masa/react-laravel-practice-public"
github_environment_name  = "stg"
github_allowed_branches  = ["main", "develop"]
tfstate_bucket           = "github-action-terraform-tf-state-bucket"
tfstate_key              = "practice/laravel/stg/terraform.tfstate"
domain_name              = "mylabinfra.com"
sub_frontend_domain_name = "stg.www"
sub_backend_domain_name  = "stg.api"
db_name                  = "practice_db"
db_username              = "admin"
parameter_store_path     = "/practice/stg/"
image_tag_nginx          = "sha-8ccd019c5528b71fefc7c547014800b27aef99be"
image_tag_laravel        = "sha-ee22fd3bafb54f8ffaf26bdc9c738c29257a38cc"
ecr_repo_name_nginx      = "react-laravel-practice-nginx-ecs"
ecr_repo_name_laravel    = "react-laravel-practice-laravel-ecs"
enable_nat_gateway       = true
app_env                  = "staging"

rds_config = {
  instance_class                  = "db.t4g.micro"
  skip_final_snapshot             = true
  enabled_cloudwatch_logs_exports = ["error"]
  multi_az                        = false
  backup_retention_period         = 0
  performance_insights_enabled    = false
  monitoring_interval             = 0
  apply_immediately               = true
}

ecs_web_service_config = {
  cpu                  = "1024"
  memory               = "2048"
  desired_count        = 2
  bake_time_in_minutes = 0
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
  ]
  autoscaling = {
    min_capacity        = 2
    max_capacity        = 4
    cpu_target_value    = 60
    memory_target_value = 70
  }
}

ecs_queue_worker_service_config = {
  cpu           = "256"
  memory        = "512"
  desired_count = 1
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
  ]
}

ecs_runner_task_config = {
  cpu    = "256"
  memory = "512"
}

ecs_batch_daily_report_task_config = {
  cpu    = "256"
  memory = "512"
  capacity_provider_strategy = [
    { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
  ]
}
