locals {
  s    = data.terraform_remote_state.stg.outputs
  name = "${var.project_name}-preview-pr${var.pr_number}"

  subdomain   = "pr-${var.pr_number}.${local.s.preview_zone_apex}"
  db_database = "preview_pr${var.pr_number}"
  queue_name  = "${local.name}-qrcode-generation"
  log_group   = "/ecs/${local.name}"
  priority    = 20000 + var.pr_number

  # web / worker / runner で共有する Laravel コンテナの環境変数
  laravel_env = [
    { name = "APP_NAME", value = "practice" },
    { name = "APP_ENV", value = "preview" },
    { name = "APP_DEBUG", value = "false" },
    { name = "APP_URL", value = "https://${local.subdomain}" },
    { name = "FRONTEND_URL", value = "https://${local.subdomain}" },
    { name = "LOG_CHANNEL", value = "stderr" },
    { name = "LOG_DEPRECATIONS_CHANNEL", value = "stderr" },
    # DB（共通 RDS 上の PR ごと database / 共通 preview ユーザー）
    { name = "DB_CONNECTION", value = "mysql" },
    { name = "DB_HOST", value = local.s.rds_address },
    { name = "DB_PORT", value = tostring(local.s.rds_port) },
    { name = "DB_DATABASE", value = local.db_database },
    { name = "DB_USERNAME", value = "preview" },
    # セッション
    { name = "SESSION_DRIVER", value = "database" },
    { name = "SESSION_LIFETIME", value = "120" },
    { name = "SESSION_SECURE", value = "true" },
    { name = "SESSION_SAME_SITE", value = "lax" },
    { name = "SESSION_PATH", value = "/" },
    # ファイル/画像（既存 stg のバケット / CDN を共有）
    { name = "FILESYSTEM_DISK", value = "s3" },
    { name = "AWS_DEFAULT_REGION", value = "ap-northeast-1" },
    { name = "AWS_BUCKET", value = local.s.image_bucket },
    { name = "AWS_URL", value = "https://${local.s.image_cdn_domain_name}" },
    { name = "AWS_USE_PATH_STYLE_ENDPOINT", value = "false" },
    # SQS（PR ごとのキュー）
    { name = "QUEUE_CONNECTION", value = "sqs" },
    { name = "SQS_PREFIX", value = "https://sqs.ap-northeast-1.amazonaws.com/${local.s.aws_account_id}" },
    { name = "SQS_QUEUE", value = local.queue_name },
    # メール（送信先は固定アドレスへ上書き）
    { name = "MAIL_MAILER", value = "ses" },
    { name = "MAIL_FROM_ADDRESS", value = "noreply@${local.s.preview_zone_apex}" },
    { name = "MAIL_FROM_NAME", value = "practice-preview" },
    { name = "MAIL_PREVIEW_REDIRECT_TO", value = var.mail_preview_redirect_to },
    # preview では Google ログイン無効
    { name = "AUTH_GOOGLE_ENABLED", value = "false" },
  ]

  laravel_secrets = [
    { name = "DB_PASSWORD", valueFrom = local.s.preview_db_password_ssm_arn },
    { name = "APP_KEY", valueFrom = local.s.app_key_ssm_arn },
  ]
}
