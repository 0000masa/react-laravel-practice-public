# =============================================================================
# Cloud Run 実行サービスアカウント（ECS タスクロール相当・キーレス）
# =============================================================================
# Laravel は静的キーを持たず、この SA の Application Default Credentials で
# Cloud SQL / Secret Manager / GCS にアクセスする。

resource "google_service_account" "run" {
  project      = var.project_id
  account_id   = "${var.project_name}-run"
  display_name = "${var.project_name} Cloud Run runtime SA"
}

# Cloud SQL コネクタ接続に必要
resource "google_project_iam_member" "run_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.run.email}"
}

# 各シークレットへの read（最小権限: シークレット単位で付与）
resource "google_secret_manager_secret_iam_member" "run_secret_accessor" {
  for_each = google_secret_manager_secret.secrets

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.run.email}"
}

# 画像バケットへの読み書き（Laravel が画像を Put/Get/Delete する）
resource "google_storage_bucket_iam_member" "run_images_admin" {
  bucket = google_storage_bucket.images.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.run.email}"
}
