# =====================================================================
# PR ごとの検証環境（preview）。terraform/pr-env/
# backend キーを PR ごとに差し替えて state を分離する（providers.tf 参照）。
# stg の state を読んで既存 ALB / VPC / ECS クラスタ / ECR / RDS / 共有リソースを再利用する。
# 詳細: docs/pr-preview-environment.md
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

# ---------------------------------------------------------------------
# ログ
# ---------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group
  retention_in_days = 7
}

# ---------------------------------------------------------------------
# per-PR タスクロール（/preview/ パス + Permissions Boundary 必須）
# 実行ロール(ECR pull / SSM)は stg の共有ロールを再利用する。
# ---------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name                 = "${local.name}-task-role"
  path                 = "/preview/"
  permissions_boundary = local.s.preview_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "task" {
  name = "${local.name}-task-policy"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Sqs"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
        Resource = aws_sqs_queue.qrcode.arn
      },
      {
        Sid      = "S3Images"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${local.s.image_bucket}/*"
      },
      {
        Sid      = "S3ImagesList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${local.s.image_bucket}"
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.this.arn}:*"
      },
      {
        Sid      = "Exec"
        Effect   = "Allow"
        Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------
# ALB ターゲットグループ + リスナールール（Host + シークレットで PR を識別）
# ---------------------------------------------------------------------
resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-pr${var.pr_number}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.s.vpc_id
  target_type = "ip"

  health_check {
    path    = "/api/health"
    matcher = "200"
  }
}

resource "aws_lb_listener_rule" "web" {
  listener_arn = local.s.alb_https_listener_arn
  priority     = local.priority

  condition {
    host_header {
      values = [local.subdomain]
    }
  }
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = [local.s.cloudfront_secret]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---------------------------------------------------------------------
# ECS web サービス（nginx + laravel。本番と同じ proxy 構成）
# ---------------------------------------------------------------------
resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name}-web"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = local.s.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "nginx-container"
      image     = "${local.s.ecr_nginx_repository_url}:${var.image_tag_nginx}"
      essential = true
      portMappings = [
        { containerPort = 80, protocol = "tcp" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },
    {
      name         = "laravel-container"
      image        = "${local.s.ecr_laravel_repository_url}:${var.image_tag_laravel}"
      essential    = true
      portMappings = [{ containerPort = 9000, protocol = "tcp" }]
      environment  = local.laravel_env
      secrets      = local.laravel_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "web" {
  name                              = "${local.name}-web"
  cluster                           = local.s.ecs_cluster_arn
  task_definition                   = aws_ecs_task_definition.web.arn
  desired_count                     = 1
  enable_execute_command            = true
  health_check_grace_period_seconds = 120

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = local.s.private_subnet_ids
    security_groups  = [local.s.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "nginx-container"
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener_rule.web]
}

# ---------------------------------------------------------------------
# SQS + queue-worker（QR 非同期。PR ごとに分離）
# ---------------------------------------------------------------------
resource "aws_sqs_queue" "qrcode" {
  name                       = local.queue_name
  visibility_timeout_seconds = 90
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.name}-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.s.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name        = "queue-worker-container"
      image       = "${local.s.ecr_laravel_repository_url}:${var.image_tag_laravel}"
      essential   = true
      command     = ["php", "artisan", "queue:work", "sqs", "--queue=${local.queue_name}", "--tries=3", "--timeout=60"]
      environment = local.laravel_env
      secrets     = local.laravel_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "worker"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "worker" {
  name            = "${local.name}-worker"
  cluster         = local.s.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = local.s.private_subnet_ids
    security_groups  = [local.s.ecs_security_group_id]
    assign_public_ip = false
  }
}

# ---------------------------------------------------------------------
# runner タスク定義（CREATE DATABASE / migrate / seed を workflow から run-task）
# command は run-task の containerOverrides で差し替える。
# ---------------------------------------------------------------------
resource "aws_ecs_task_definition" "runner" {
  family                   = "${local.name}-runner"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = local.s.ecs_task_execution_role_arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name        = "runner-container"
      image       = "${local.s.ecr_laravel_repository_url}:${var.image_tag_laravel}"
      essential   = true
      environment = local.laravel_env
      secrets     = local.laravel_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "runner"
        }
      }
    }
  ])
}

# ---------------------------------------------------------------------
# フロント配信用 S3 バケット（PR ごと）。terraform destroy でバケットごと削除される。
# ---------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket        = "${local.name}-frontend"
  force_destroy = true
  tags = {
    Name = "${local.name}-frontend"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend-oac"
  description                       = "OAC for ${local.name} frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 本番同様、このPRの CloudFront からのみ読み取りを許可（SourceArn で厳格化）
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------
# CloudFront（PR ごと）。viewer = pr-<n>.preview.<domain>
# ---------------------------------------------------------------------
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = local.name
  default_root_object = "index.html"
  aliases             = [local.subdomain]
  web_acl_id          = local.s.preview_waf_web_acl_arn

  # フロント（PR ごとのバケット。ルートに配置するので origin_path 不要）
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # API（共有 ALB オリジン）。X-CloudFront-Secret を注入し、Host は all_viewer で転送。
  origin {
    domain_name = local.s.preview_api_origin_host
    origin_id   = "backend-api"

    custom_header {
      name  = "X-CloudFront-Secret"
      value = local.s.cloudfront_secret
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "s3-frontend"
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.s3_cors.id

    function_association {
      event_type   = "viewer-request"
      function_arn = local.s.spa_fallback_function_arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "backend-api"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = local.s.preview_cf_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ---------------------------------------------------------------------
# viewer DNS: pr-<n>.preview.<domain> → CloudFront
# ---------------------------------------------------------------------
resource "aws_route53_record" "viewer_a" {
  zone_id = local.s.route53_zone_id
  name    = local.subdomain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "viewer_aaaa" {
  zone_id = local.s.route53_zone_id
  name    = local.subdomain
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
