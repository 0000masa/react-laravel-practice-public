# =============================================================================
# import ブロック（config-driven import）
# =============================================================================
# 「手作業作成 → import」フロー用のテンプレート。
#
# 使い方:
#   1. コンソール / gcloud で各リソースを手動作成する（README のチェックリスト参照）
#   2. 該当ブロックのコメントを外し、id を実際の値に合わせる
#      （<PROJECT_ID> は terraform.tfvars の project_id に置換）
#   3. terraform plan -generate-config-out=generated.tf でも確認できるが、
#      ここでは既に .tf を書いてあるので import 後に `terraform plan` 差分ゼロを目指す
#   4. terraform apply で state に取り込まれる。差分が出たら .tf か手動設定を寄せて収束させる
#
# id 形式は google provider のドキュメント準拠。代表的なものを列挙する。

# --- API 有効化（for_each: サービス名がキー）---------------------------------
# import {
#   to = module.app.google_project_service.apis["run.googleapis.com"]
#   id = "<PROJECT_ID>/run.googleapis.com"
# }

# --- Artifact Registry -------------------------------------------------------
# import 対象ではない。AR は Terraform 非管理（data 参照）に変更したため、import せず
# コンソールで作成済みのリポジトリを data で参照するだけ（手順3）。最初の plan より前に存在が必須。
# 詳細は docs/adr/0003-artifact-registry-unmanaged.md。

# --- Cloud SQL ----------------------------------------------------------------
# import {
#   to = module.app.google_sql_database_instance.main
#   id = "<PROJECT_ID>/practice-gcp-stg-mysql"
# }
# import {
#   to = module.app.google_sql_database.main
#   id = "projects/<PROJECT_ID>/instances/practice-gcp-stg-mysql/databases/practice_db"
# }
# import {
#   to = module.app.google_sql_user.main
#   id = "<PROJECT_ID>/practice-gcp-stg-mysql/admin"
# }

# --- Secret Manager（for_each）-----------------------------------------------
# import {
#   to = module.app.google_secret_manager_secret.secrets["app_key"]
#   id = "projects/<PROJECT_ID>/secrets/practice-gcp-stg-app-key"
# }
# （db_password / google_client_id / google_client_secret も同様）

# --- サービスアカウント -------------------------------------------------------
# import {
#   to = module.app.google_service_account.run
#   id = "projects/<PROJECT_ID>/serviceAccounts/practice-gcp-stg-run@<PROJECT_ID>.iam.gserviceaccount.com"
# }

# --- GCS ----------------------------------------------------------------------
# import {
#   to = module.app.google_storage_bucket.frontend
#   id = "practice-gcp-stg-frontend"
# }
# import {
#   to = module.app.google_storage_bucket.images
#   id = "practice-gcp-stg-images"
# }

# --- Cloud Run ----------------------------------------------------------------
# import {
#   to = module.app.google_cloud_run_v2_service.web
#   id = "projects/<PROJECT_ID>/locations/asia-northeast1/services/practice-gcp-stg-web"
# }
# import {
#   to = module.app.google_cloud_run_v2_job.migrate
#   id = "projects/<PROJECT_ID>/locations/asia-northeast1/jobs/practice-gcp-stg-migrate"
# }

# --- ロードバランサ周り（global）---------------------------------------------
# import {
#   to = module.app.google_compute_global_address.lb
#   id = "projects/<PROJECT_ID>/global/addresses/practice-gcp-stg-lb-ip"
# }
# import {
#   to = module.app.google_compute_region_network_endpoint_group.run
#   id = "projects/<PROJECT_ID>/regions/asia-northeast1/networkEndpointGroups/practice-gcp-stg-run-neg"
# }
# import {
#   to = module.app.google_compute_backend_service.run
#   id = "projects/<PROJECT_ID>/global/backendServices/practice-gcp-stg-run-backend"
# }
# import {
#   to = module.app.google_compute_backend_bucket.frontend
#   id = "projects/<PROJECT_ID>/global/backendBuckets/practice-gcp-stg-frontend-backend"
# }
# import {
#   to = module.app.google_compute_backend_bucket.images
#   id = "projects/<PROJECT_ID>/global/backendBuckets/practice-gcp-stg-images-backend"
# }
# import {
#   to = module.app.google_compute_url_map.main
#   id = "projects/<PROJECT_ID>/global/urlMaps/practice-gcp-stg-urlmap"
# }
# import {
#   to = module.app.google_compute_managed_ssl_certificate.main
#   id = "projects/<PROJECT_ID>/global/sslCertificates/practice-gcp-stg-cert"
# }
# import {
#   to = module.app.google_compute_target_https_proxy.main
#   id = "projects/<PROJECT_ID>/global/targetHttpsProxies/practice-gcp-stg-https-proxy"
# }
# import {
#   to = module.app.google_compute_global_forwarding_rule.https
#   id = "projects/<PROJECT_ID>/global/forwardingRules/practice-gcp-stg-https-fr"
# }
# （redirect 用 url_map / target_http_proxy / forwarding_rule.http も同様）

# --- Cloud DNS ----------------------------------------------------------------
# import {
#   to = module.app.google_dns_managed_zone.main
#   id = "<PROJECT_ID>/practice-gcp-stg-zone"
# }
# import {
#   to = module.app.google_dns_record_set.app
#   id = "<PROJECT_ID>/practice-gcp-stg-zone/example-gcp.com./A"
# }

# --- CI: Workload Identity Federation / デプロイ SA --------------------------
# import {
#   to = module.app.google_iam_workload_identity_pool.github
#   id = "projects/<PROJECT_ID>/locations/global/workloadIdentityPools/practice-gcp-stg-gh-pool"
# }
# import {
#   to = module.app.google_iam_workload_identity_pool_provider.github
#   id = "projects/<PROJECT_ID>/locations/global/workloadIdentityPools/practice-gcp-stg-gh-pool/providers/practice-gcp-stg-gh-provider"
# }
# import {
#   to = module.app.google_service_account.gha_push["nginx"]
#   id = "projects/<PROJECT_ID>/serviceAccounts/practice-gcp-stg-push-nginx@<PROJECT_ID>.iam.gserviceaccount.com"
# }
# import {
#   to = module.app.google_service_account.gha_push["laravel"]
#   id = "projects/<PROJECT_ID>/serviceAccounts/practice-gcp-stg-push-laravel@<PROJECT_ID>.iam.gserviceaccount.com"
# }
# IAM バインディング（artifactregistry.writer / workloadIdentityUser）は
# google_*_iam_member。import する場合の id 形式は provider ドキュメント参照。
