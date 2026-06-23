# =============================================================================
# Cloud SQL for MySQL 8.0（RDS 相当）
# =============================================================================
# VPC を作らない方針のため公開 IP を有効化し、Cloud Run からは Cloud SQL コネクタ
# （Unix ソケット /cloudsql/<connection_name>）で接続する。
# authorized_networks は開けない（コネクタが IAM/SSL で認証するため不要）。

resource "google_sql_database_instance" "main" {
  project          = var.project_id
  name             = "${var.project_name}-mysql"
  region           = var.region
  database_version = "MYSQL_8_0"

  deletion_protection = var.cloudsql_config.deletion_protection

  settings {
    tier              = var.cloudsql_config.tier
    availability_type = var.cloudsql_config.availability_type
    disk_size         = var.cloudsql_config.disk_size
    disk_type         = "PD_SSD"

    ip_configuration {
      # 公開 IP を有効化（コネクタ経由でのみ使用）。VPC private network は付与しない。
      ipv4_enabled = true
      # 直接の TCP 接続を許可するネットワークは登録しない（コネクタ専用）。
      ssl_mode = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled = var.cloudsql_config.backup_enabled
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "main" {
  project   = var.project_id
  name      = var.db_name
  instance  = google_sql_database_instance.main.name
  charset   = "utf8mb4"
  collation = "utf8mb4_unicode_ci"
}

resource "google_sql_user" "main" {
  project  = var.project_id
  name     = var.db_username
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}
