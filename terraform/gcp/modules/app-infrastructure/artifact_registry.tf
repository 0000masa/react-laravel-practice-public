# =============================================================================
# Artifact Registry（ECR 相当）— Terraform 非管理（data 参照）
# =============================================================================
# AWS 版が ECR を `data "aws_ecr_repository"` 参照（Terraform 外で作成）にしているのに合わせ、
# GCP でも Artifact Registry を **data 参照（非管理）** にする。理由:
#   - レジストリのライフサイクルを app インフラの apply サイクルから分離する。
#   - 「空 AR 作成 → push → Cloud Run 作成」の単一スタック内の順序依存（鶏卵）を原理的に消す。
#   - AWS（ECR=data）と構成を揃える。
# 詳細は docs/adr/0003-artifact-registry-unmanaged.md。
#
# data 参照なので **最初の `terraform plan` より前にリポジトリが存在している必要がある**
# （コンソールで作成。手順3）。タグ不変（immutable tags）はレジストリ側＝コンソールで設定する
# （非管理のため Terraform では設定できない）。
#   asia-northeast1-docker.pkg.dev/<project>/nginx/nginx:<tag>
#   asia-northeast1-docker.pkg.dev/<project>/laravel/laravel:<tag>

locals {
  ar_repos = toset(["nginx", "laravel"])
}

data "google_artifact_registry_repository" "repos" {
  for_each = local.ar_repos

  project       = var.project_id
  location      = var.region
  repository_id = each.value
}

locals {
  registry_host = "${var.region}-docker.pkg.dev/${var.project_id}"
  image_nginx   = "${local.registry_host}/${data.google_artifact_registry_repository.repos["nginx"].repository_id}/nginx:${var.image_tag_nginx}"
  image_laravel = "${local.registry_host}/${data.google_artifact_registry_repository.repos["laravel"].repository_id}/laravel:${var.image_tag_laravel}"
}
