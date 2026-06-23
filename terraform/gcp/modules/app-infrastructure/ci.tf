# =============================================================================
# CI 認証: Workload Identity Federation（AWS の GitHub OIDC ロール相当）
# =============================================================================
# GitHub Actions が長期キーなしで Artifact Registry に push できるようにする。
# - Workload Identity Pool + GitHub OIDC Provider
# - デプロイ SA をリポジトリ（nginx / laravel）ごとに分割し、各 SA は自分のリポジトリにのみ
#   artifactregistry.writer を持つ（AWS 版の用途別ロール = 最小権限に一貫）。
# - 対象 GitHub リポジトリだけが各 SA を impersonate できるよう principalSet を絞る。

# Workload Identity Pool: GitHub Actions など「GCP 外の ID」を principal 化するための入れ物（名前空間）。
# 鍵は保管しない。この中の Provider が受理したトークンを principalSet として参照できるようにする土台。
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.project_name}-gh-pool"
  display_name              = "${var.project_name} GitHub pool"

  depends_on = [google_project_service.apis]
}

# Pool Provider: 信頼する OIDC 発行元（GitHub）と、トークンのクレーム→属性マッピング、
# 受理条件（attribute_condition）を設定する＝「どのトークンをこのプールで受け入れるか」の入口ゲート。
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.project_name}-gh-provider"
  display_name                       = "GitHub Actions OIDC"

  # OIDC トークンのクレーム（右）を WIF の属性（左）に写す。principalSet や条件はこの属性で参照する。
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # 対象リポジトリのトークンだけ受け付ける（他リポジトリからの悪用を防ぐ）
  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# --- イメージ push 用 SA（リポジトリごと: nginx / laravel）---------------------
# gcp-ar-push-*.yml が impersonate して AR に build & push するための SA。
# Cloud Run 更新用の deploy SA（run_deployer, 後述）とは別物。push と deploy で関心を分離している。
resource "google_service_account" "gha_push" {
  for_each = local.ar_repos

  project      = var.project_id
  account_id   = "${var.project_name}-push-${each.value}"
  display_name = "${var.project_name} GitHub Actions push (${each.value})"
}

# 各 SA は自分のリポジトリにのみ writer
# AR は data 参照（非管理）だが、リポジトリ「への」IAM バインディングは Terraform で管理できる
# （AWS 版が ECR=data 参照のまま GHA 用 IAM ポリシーを管理しているのと同じ）。
resource "google_artifact_registry_repository_iam_member" "push" {
  for_each = local.ar_repos

  project    = var.project_id
  location   = var.region
  repository = data.google_artifact_registry_repository.repos[each.value].name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.gha_push[each.value].email}"
}

# =============================================================================
# CI 認証（その2）: Cloud Run 更新用のデプロイ SA
# =============================================================================
# イメージの「ビルド & push」(gha_push) とは別に、push 済みイメージで Cloud Run サービス/ジョブを
# 更新する deploy ワークフロー（gcp-run-deploy-*.yml）用の SA。push と関心を分離し最小権限にする。
# - run.developer は **対象サービス / ジョブ単位**に付与（プロジェクト全体には付けない）。
# - サービス/ジョブが「として動く」ランタイム SA（run）に対する serviceAccountUser（actAs）が必須。
# - 環境（stg/prod）ごとに別 SA。prod は prod インフラ構築時に同名で作る（practice-gcp-prod-run-deployer）。
# 詳細は docs/adr/0004-cloudrun-deploy-via-gha.md。
resource "google_service_account" "run_deployer" {
  project      = var.project_id
  account_id   = "${var.project_name}-run-deployer"
  display_name = "${var.project_name} Cloud Run deployer (GitHub Actions)"
}

# サービス（web）を更新する権限（対象サービス単位）
resource "google_cloud_run_v2_service_iam_member" "deployer_service" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.run_deployer.email}"
}

# migrate ジョブを更新・実行する権限（対象ジョブ単位）
resource "google_cloud_run_v2_job_iam_member" "deployer_job" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.migrate.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.run_deployer.email}"
}

# 「ランタイム SA として動く」サービス/ジョブをデプロイするための actAs 権限
resource "google_service_account_iam_member" "deployer_act_as_runtime" {
  service_account_id = google_service_account.run.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.run_deployer.email}"
}

# 対象 GitHub リポジトリからのみ deploy SA を impersonate 可能にする（push SA と同じ仕組み）
resource "google_service_account_iam_member" "wif_deployer" {
  service_account_id = google_service_account.run_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# 対象 GitHub リポジトリからのみ各 SA を impersonate 可能にする
resource "google_service_account_iam_member" "wif_push" {
  for_each = local.ar_repos

  service_account_id = google_service_account.gha_push[each.value].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}
