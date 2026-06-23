# =============================================================================
# Secret Manager（AWS の SSM Parameter Store / SecureString 相当）
# =============================================================================
# Cloud Run に渡すシークレットは4つ:
#   - db_password        … TF が random_password で生成し、バージョンも TF 管理
#   - app_key            … `php artisan key:generate --show` の値を手動投入
#   - google_client_id   … Google OAuth クライアント ID を手動投入
#   - google_client_secret … 同シークレットを手動投入
#
# app_key / google_* は機密かつ外部由来のため、シークレット「コンテナ」だけ TF で作り、
# バージョン（値）は手動で追加する（README 参照）。Cloud Run は version="latest" を参照する。

locals {
  secret_ids = {
    db_password          = "${var.project_name}-db-password"
    app_key              = "${var.project_name}-app-key"
    google_client_id     = "${var.project_name}-google-client-id"
    google_client_secret = "${var.project_name}-google-client-secret"
  }
}

resource "google_secret_manager_secret" "secrets" {
  for_each = local.secret_ids

  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

# --- DB パスワードのみ TF 生成 + バージョン投入 -------------------------------
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%*-_"
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.secrets["db_password"].id
  secret_data = random_password.db.result
}
