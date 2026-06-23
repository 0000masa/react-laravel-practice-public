# =============================================================================
# 入力変数
# =============================================================================

variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "project_name" {
  description = "リソース名のプレフィックス（例: practice-gcp-stg）"
  type        = string
}

variable "region" {
  description = "リージョン（Cloud Run / Cloud SQL / GCS / Artifact Registry）"
  type        = string
  default     = "asia-northeast1"
}

variable "app_env" {
  description = "Laravel の APP_ENV"
  type        = string
  default     = "staging"
}

# --- ドメイン / DNS -----------------------------------------------------------

variable "domain_name" {
  description = "アプリ（フロント + API）の単一ドメイン。今は仮名でよい（例: example-gcp.com）"
  type        = string
}

variable "image_domain_name" {
  description = "画像配信用ドメイン（例: img.example-gcp.com）"
  type        = string
}

variable "dns_managed_zone_dns_name" {
  description = "Cloud DNS マネージドゾーンの DNS 名（末尾ドット付き。例: example-gcp.com.）"
  type        = string
}

# --- Cloud SQL ----------------------------------------------------------------

variable "cloudsql_config" {
  description = "Cloud SQL (MySQL) の設定"
  type = object({
    tier                = string # 例: db-f1-micro
    availability_type   = string # ZONAL / REGIONAL
    disk_size           = number
    backup_enabled      = bool
    deletion_protection = bool
  })
  default = {
    tier                = "db-f1-micro"
    availability_type   = "ZONAL"
    disk_size           = 10
    backup_enabled      = false
    deletion_protection = false
  }
}

variable "db_name" {
  description = "データベース名"
  type        = string
  default     = "practice_db"
}

variable "db_username" {
  description = "DB ユーザー名"
  type        = string
  default     = "admin"
}

# --- Cloud Run ----------------------------------------------------------------

variable "cloud_run_config" {
  description = "Cloud Run サービス（Web）の設定"
  type = object({
    cpu           = string # 例: "1"
    memory        = string # 例: "512Mi"
    min_instances = number
    max_instances = number
  })
  default = {
    cpu           = "1"
    memory        = "512Mi"
    min_instances = 0
    max_instances = 2
  }
}

# --- コンテナイメージ ---------------------------------------------------------
# Artifact Registry に push 済みのイメージタグを指定する。
variable "image_tag_nginx" {
  description = "nginx イメージタグ"
  type        = string
}

variable "image_tag_laravel" {
  description = "laravel(php-fpm) イメージタグ"
  type        = string
}

# --- CI（GitHub Actions / WIF）-----------------------------------------------
variable "github_repository" {
  description = "GitHub リポジトリ（owner/repo）。WIF の信頼条件に使う"
  type        = string
}
