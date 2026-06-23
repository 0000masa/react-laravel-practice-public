# =============================================================================
# Cloud Storage（S3 相当）
# =============================================================================
# - frontend: React SPA の静的アセット。SPA フォールバックのため 404 を index.html に。
# - images:   QR / ユーザー画像。公開 read で Cloud CDN 配信。
# どちらも LB のバックエンドバケットとして配信するため、オブジェクトは allUsers 読み取り可にする。

# --- フロントエンド配信バケット ----------------------------------------------
resource "google_storage_bucket" "frontend" {
  project                     = var.project_id
  name                        = "${var.project_name}-frontend"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html" # SPA フォールバック（CloudFront Functions 相当）
  }
}

resource "google_storage_bucket_iam_member" "frontend_public" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# --- 画像配信バケット ---------------------------------------------------------
# CORS は設定しない: QR / ユーザー画像はフロントで素の <img src> 表示のみ（fetch / canvas で
# 中身を読まない）。クロスオリジンの <img> 埋め込みは CORS を要求しないため不要。将来 fetch や
# canvas（ダウンロード機能等）で読むなら cors{} を足す。
resource "google_storage_bucket" "images" {
  project                     = var.project_id
  name                        = "${var.project_name}-images"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket_iam_member" "images_public" {
  bucket = google_storage_bucket.images.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
