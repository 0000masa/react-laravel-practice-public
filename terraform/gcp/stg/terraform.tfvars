project_id   = "your-gcp-project-id" # ← 実際の GCP プロジェクト ID に置き換える
project_name = "practice-gcp-stg"
region       = "asia-northeast1"
app_env      = "staging"

# ドメインは仮名。本番ドメイン取得後に差し替える。
domain_name               = "example-gcp.com"
image_domain_name         = "img.example-gcp.com"
dns_managed_zone_dns_name = "example-gcp.com."

github_repository = "0000masa/react-laravel-practice-public"

db_name     = "practice_db"
db_username = "admin"

# bootstrap 専用シード: Cloud Run の初回 apply 時の参照イメージにだけ使う。
# 初回 apply より前に push 済みの sha タグ（例 sha-xxxxxxx）を設定すること。
# 初回作成後はライブイメージを GitHub Actions の deploy ワークフローが所有し（ignore_changes）、
# ここを変えても再デプロイされない。タグは immutable（latest のような移動タグは使わない）。
image_tag_nginx   = "sha-REPLACE_WITH_PUSHED_SHA"
image_tag_laravel = "sha-REPLACE_WITH_PUSHED_SHA"

cloudsql_config = {
  tier                = "db-f1-micro"
  availability_type   = "ZONAL"
  disk_size           = 10
  backup_enabled      = false
  deletion_protection = false
}

cloud_run_config = {
  cpu           = "1"
  memory        = "512Mi"
  min_instances = 0
  max_instances = 2
}
