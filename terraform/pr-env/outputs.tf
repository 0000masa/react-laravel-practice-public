output "preview_url" {
  description = "検証環境の URL"
  value       = "https://${local.subdomain}"
}

output "db_database" {
  description = "この PR の database 名（runner で CREATE/migrate/seed する対象）"
  value       = local.db_database
}

output "ecs_cluster_arn" {
  value = local.s.ecs_cluster_arn
}

output "runner_task_definition_family" {
  description = "DB 作成/migrate/seed を run-task する対象タスク定義"
  value       = aws_ecs_task_definition.runner.family
}

output "private_subnet_ids" {
  value = local.s.private_subnet_ids
}

output "ecs_security_group_id" {
  value = local.s.ecs_security_group_id
}

output "preview_frontend_bucket" {
  description = "共有 frontend バケット（このPRは pr-<n>/ プレフィックスへアップロード）"
  value       = local.s.preview_frontend_bucket
}

output "pr_prefix" {
  value = "pr-${var.pr_number}"
}
