# =============================================================================
# 必要な GCP API の有効化
# =============================================================================
# 手作業で先に有効化しておき、import する想定。
# disable_on_destroy = false で、terraform destroy 時に API まで無効化しないようにする。

locals {
  required_apis = [
    "run.googleapis.com",              # Cloud Run
    "sqladmin.googleapis.com",         # Cloud SQL
    "secretmanager.googleapis.com",    # Secret Manager
    "artifactregistry.googleapis.com", # Artifact Registry
    "compute.googleapis.com",          # 外部 HTTPS LB / Cloud CDN / グローバル IP
    "dns.googleapis.com",              # Cloud DNS
    "iam.googleapis.com",
    "iamcredentials.googleapis.com", # 署名付き URL（signBlob）/ WIF
    "sts.googleapis.com",            # Workload Identity Federation のトークン交換
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
