# =====================================================================
# PR ごとの検証環境（preview）。terraform/pr-env/
# backend キーを PR ごとに差し替えて state を分離する（providers.tf 参照）。
# stg の state を読んで既存 ALB / VPC / ECS クラスタ / ECR / RDS / 共有リソースを再利用する。
# 詳細: docs/deploy/pr-preview-environment.md
# =====================================================================

data "terraform_remote_state" "stg" {
  backend = "s3"
  config = {
    bucket = var.stg_state_bucket
    key    = var.stg_state_key
    region = "ap-northeast-1"
  }
}

# CloudFront マネージドポリシー（stg と同じものを使う）
data "aws_cloudfront_cache_policy" "caching_optimized" { name = "Managed-CachingOptimized" }
data "aws_cloudfront_cache_policy" "caching_disabled" { name = "Managed-CachingDisabled" }
data "aws_cloudfront_origin_request_policy" "all_viewer" { name = "Managed-AllViewer" }
data "aws_cloudfront_origin_request_policy" "s3_cors" { name = "Managed-CORS-S3Origin" }
