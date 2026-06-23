# =============================================================================
# Cloud DNS（Route53 相当）
# =============================================================================
# 新規取得予定ドメインのマネージドゾーン。レジストラ側の NS をこのゾーンの
# name_servers に委譲する前提（本番ドメイン取得後）。
# app / images 両ドメインの A レコードを LB のグローバル IP に向ける。

resource "google_dns_managed_zone" "main" {
  project     = var.project_id
  name        = "${var.project_name}-zone"
  dns_name    = var.dns_managed_zone_dns_name
  description = "${var.project_name} public zone"

  depends_on = [google_project_service.apis]
}

resource "google_dns_record_set" "app" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "${var.domain_name}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb.address]
}

resource "google_dns_record_set" "images" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "${var.image_domain_name}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.lb.address]
}
