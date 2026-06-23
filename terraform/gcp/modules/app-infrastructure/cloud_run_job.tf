# =============================================================================
# Cloud Run Job（DB マイグレーション / シード・単発 Runner 相当）
# =============================================================================
# AWS の ECS RunTask（migrate/seed）の最小版。VPC を作らないため、Job も Cloud SQL
# コネクタ経由で接続する。実行は手動: `gcloud run jobs execute <name>`。

resource "google_cloud_run_v2_job" "migrate" {
  project             = var.project_id
  name                = "${var.project_name}-migrate"
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.run.email

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [google_sql_database_instance.main.connection_name]
        }
      }

      containers {
        image   = local.image_laravel
        command = ["php"]
        args    = ["artisan", "migrate", "--force"]

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }

        dynamic "env" {
          for_each = local.run_env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = local.run_secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = google_secret_manager_secret.secrets[env.value].secret_id
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [google_project_service.apis]

  # サービスと同じく、ライブイメージは deploy ワークフローが所有する（laravel deploy が
  # 「ジョブ image 更新 → 実行 → サービス更新」を行う）。Terraform は初回作成シードのみ。
  # ジョブは template→template→containers の入れ子。コンテナは1つ（index 0 = laravel）。
  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image, # laravel
    ]
  }
}
