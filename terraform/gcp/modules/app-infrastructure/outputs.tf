# =============================================================================
# 出力
# =============================================================================

output "lb_ip_address" {
  description = "LB のグローバル IP。DNS の A レコード（委譲先レジストラ）に設定する値。"
  value       = google_compute_global_address.lb.address
}

output "dns_name_servers" {
  description = "Cloud DNS ゾーンの NS。レジストラ側でこの NS に委譲する。"
  value       = google_dns_managed_zone.main.name_servers
}

output "cloud_run_service_name" {
  value = google_cloud_run_v2_service.web.name
}

output "cloud_run_uri" {
  description = "Cloud Run の URL（ingress 制限のため直叩きは不可。確認用）"
  value       = google_cloud_run_v2_service.web.uri
}

output "cloudsql_connection_name" {
  description = "Cloud SQL 接続名（コネクタ / gcloud sql connect で使用）"
  value       = google_sql_database_instance.main.connection_name
}

output "migrate_job_name" {
  value = google_cloud_run_v2_job.migrate.name
}

output "artifact_registry_host" {
  description = "Artifact Registry のホスト（<region>-docker.pkg.dev/<project>）"
  value       = local.registry_host
}

output "frontend_bucket" {
  value = google_storage_bucket.frontend.name
}

# --- CI（GitHub Actions secrets に設定する値）---------------------------------
output "wif_provider" {
  description = "GHA secret GCP_WIF_PROVIDER に設定する WIF プロバイダのフルリソース名"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "gha_push_service_accounts" {
  description = "GHA secret に設定する push 用 SA のメール（リポジトリごと）"
  value       = { for k, sa in google_service_account.gha_push : k => sa.email }
}

output "run_deploy_service_account" {
  description = "GHA Environment secret GCP_RUN_DEPLOY_SA に設定する Cloud Run 更新用 SA のメール"
  value       = google_service_account.run_deployer.email
}

output "image_bucket" {
  value = google_storage_bucket.images.name
}
