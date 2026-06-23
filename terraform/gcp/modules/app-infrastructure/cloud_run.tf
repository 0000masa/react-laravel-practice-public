# =============================================================================
# Cloud Run（Web サービス・マルチコンテナ: nginx + php-fpm）
# =============================================================================
# ingress = INTERNAL_LOAD_BALANCER で run.app 直叩きを遮断し、LB 経由のみ許可する
# （AWS の「ALB 403 + 秘密ヘッダー」によるオリジン保護の GCP ネイティブ版）。

locals {
  # 非機密の環境変数
  run_env = {
    APP_NAME     = var.project_name
    APP_ENV      = var.app_env
    APP_DEBUG    = "false"
    APP_URL      = "https://${var.domain_name}"
    FRONTEND_URL = "https://${var.domain_name}"

    LOG_CHANNEL              = "stderr"
    LOG_DEPRECATIONS_CHANNEL = "stderr"

    # Cloud SQL コネクタ（Unix ソケット）経由の接続
    DB_CONNECTION = "mysql"
    DB_SOCKET     = "/cloudsql/${google_sql_database_instance.main.connection_name}"
    DB_DATABASE   = var.db_name
    DB_USERNAME   = var.db_username

    SESSION_DRIVER    = "database"
    SESSION_LIFETIME  = "120"
    SESSION_SECURE    = "true"
    SESSION_SAME_SITE = "lax"
    SESSION_PATH      = "/"

    # コア構成: 非同期キューは同期化、メールはログドライバ
    QUEUE_CONNECTION = "sync"
    MAIL_MAILER      = "log"

    # GCS（Flysystem GCS アダプタ・ADC でキーレス）
    FILESYSTEM_DISK              = "gcs"
    GOOGLE_CLOUD_PROJECT_ID      = var.project_id
    GOOGLE_CLOUD_STORAGE_BUCKET  = google_storage_bucket.images.name
    GOOGLE_CLOUD_STORAGE_API_URI = "https://${var.image_domain_name}"

    GOOGLE_REDIRECT_URI = "https://${var.domain_name}/api/auth/google/callback"
  }

  # Secret Manager 由来の環境変数（env 名 => シークレットのキー）
  run_secret_env = {
    APP_KEY              = "app_key"
    DB_PASSWORD          = "db_password"
    GOOGLE_CLIENT_ID     = "google_client_id"
    GOOGLE_CLIENT_SECRET = "google_client_secret"
  }
}

resource "google_cloud_run_v2_service" "web" {
  project             = var.project_id
  name                = "${var.project_name}-web"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  deletion_protection = false

  template {
    service_account = google_service_account.run.email

    scaling {
      min_instance_count = var.cloud_run_config.min_instances
      max_instance_count = var.cloud_run_config.max_instances
    }

    # Cloud SQL コネクタ用ボリューム
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    # ingress コンテナ: nginx（Cloud Run が 80 番に流す）
    containers {
      name  = "nginx"
      image = local.image_nginx

      ports {
        container_port = 80
      }

      resources {
        limits = {
          cpu    = var.cloud_run_config.cpu
          memory = var.cloud_run_config.memory
        }
      }

      # php-fpm が起動してから nginx を上げる
      depends_on = ["laravel"]
    }

    # サイドカー: php-fpm（Laravel）
    containers {
      name  = "laravel"
      image = local.image_laravel

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

  depends_on = [google_project_service.apis]

  # ライブイメージは GitHub Actions の deploy ワークフロー（gcp-run-deploy-*.yml）が所有する。
  # Terraform は image を管理せず、初回作成時のシード（tfvars の image_tag_*）にのみ使う。
  # index は .tf のコンテナ記述順に対応（0=nginx / 1=laravel）。順序を変えると ignore 対象がズレる。
  # 詳細は docs/adr/0004-cloudrun-deploy-via-gha.md。
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image, # nginx
      template[0].containers[1].image, # laravel
    ]
  }
}

# LB（Serverless NEG）からの呼び出しを許可。ingress 制限と併用で「LB 経由のみ」を実現。
resource "google_cloud_run_v2_service_iam_member" "web_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
