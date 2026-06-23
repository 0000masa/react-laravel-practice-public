# =============================================================================
# 外部 HTTPS ロードバランサ + Cloud CDN（CloudFront + ALB 相当）
# =============================================================================
# 単一の Global External Application LB に3つのバックエンドをぶら下げる:
#   - frontend backend bucket（SPA・CDN 有効） … 既定
#   - run backend service（Serverless NEG → Cloud Run） … /api/*
#   - images backend bucket（画像・CDN 有効） … 画像用ドメイン
#
# ホスト / パスの振り分け:
#   <domain_name>        : /api/* → Cloud Run, それ以外 → frontend bucket
#   <image_domain_name>  : 全部 → images bucket

# --- グローバル静的 IP --------------------------------------------------------
resource "google_compute_global_address" "lb" {
  project = var.project_id
  name    = "${var.project_name}-lb-ip"
}

# --- Cloud Run 用 Serverless NEG ---------------------------------------------
resource "google_compute_region_network_endpoint_group" "run" {
  project               = var.project_id
  name                  = "${var.project_name}-run-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.web.name
  }
}

resource "google_compute_backend_service" "run" {
  project               = var.project_id
  name                  = "${var.project_name}-run-backend"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.run.id
  }
}

# --- バックエンドバケット（CDN 有効）-----------------------------------------
resource "google_compute_backend_bucket" "frontend" {
  project     = var.project_id
  name        = "${var.project_name}-frontend-backend"
  bucket_name = google_storage_bucket.frontend.name
  enable_cdn  = true
}

resource "google_compute_backend_bucket" "images" {
  project     = var.project_id
  name        = "${var.project_name}-images-backend"
  bucket_name = google_storage_bucket.images.name
  enable_cdn  = true

  cdn_policy {
    cache_mode  = "CACHE_ALL_STATIC"
    default_ttl = 3600
    max_ttl     = 86400
  }
}

# --- URL マップ（ホスト / パス振り分け）--------------------------------------
resource "google_compute_url_map" "main" {
  project         = var.project_id
  name            = "${var.project_name}-urlmap"
  default_service = google_compute_backend_bucket.frontend.id

  host_rule {
    hosts        = [var.domain_name]
    path_matcher = "app"
  }

  host_rule {
    hosts        = [var.image_domain_name]
    path_matcher = "images"
  }

  path_matcher {
    name            = "app"
    default_service = google_compute_backend_bucket.frontend.id

    path_rule {
      paths   = ["/api", "/api/*"]
      service = google_compute_backend_service.run.id
    }
  }

  path_matcher {
    name            = "images"
    default_service = google_compute_backend_bucket.images.id
  }
}

# --- Google マネージド SSL 証明書 --------------------------------------------
# ドメインが LB の IP を指し、DNS 委譲が効くまで ACTIVE にならない点に注意。
resource "google_compute_managed_ssl_certificate" "main" {
  project = var.project_id
  name    = "${var.project_name}-cert"

  managed {
    domains = [var.domain_name, var.image_domain_name]
  }
}

# --- HTTPS フロントエンド -----------------------------------------------------
resource "google_compute_target_https_proxy" "main" {
  project          = var.project_id
  name             = "${var.project_name}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main.id]
}

resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = "${var.project_name}-https-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.id
  port_range            = "443"
  target                = google_compute_target_https_proxy.main.id
}

# --- HTTP → HTTPS リダイレクト ------------------------------------------------
resource "google_compute_url_map" "redirect" {
  project = var.project_id
  name    = "${var.project_name}-redirect"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  project = var.project_id
  name    = "${var.project_name}-http-proxy"
  url_map = google_compute_url_map.redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project               = var.project_id
  name                  = "${var.project_name}-http-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.id
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect.id
}
