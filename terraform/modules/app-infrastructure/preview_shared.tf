# =====================================================================
# PR ごとの検証環境（preview）の「共有 / ブートストラップ」リソース
# =====================================================================
# 1 回だけ作成し、全 PR の preview が共有する。PR ごとのリソースは
# terraform/pr-env/ が作る（このファイルでは作らない）。
# 詳細: docs/pr-preview-environment.md

locals {
  preview_zone_apex   = "preview.${var.domain_name}"     # 例: preview.mylabinfra.com
  preview_wildcard    = "*.preview.${var.domain_name}"   # viewer: pr-<n>.preview.<domain>
  preview_api_origin  = "api.preview.${var.domain_name}" # 共有 ALB オリジン（CloudFront の /api 用）
  preview_oidc_sub    = "repo:${var.github_repository}:environment:${var.preview_github_environment_name}"
  preview_role_prefix = "preview-pr" # per-PR ロールの命名（pr-env と合わせる）
}

# ---------------------------------------------------------------------
# ワイルドカード ACM 証明書（CloudFront 用 = us-east-1）
# ---------------------------------------------------------------------
resource "aws_acm_certificate" "preview_cf" {
  provider          = aws.us_east_1
  domain_name       = local.preview_wildcard
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------
# ワイルドカード ACM 証明書（ALB 用 = ap-northeast-1）
# CloudFront → ALB(api.preview...) のオリジン TLS 用。ALB の HTTPS リスナーに追加する。
# ---------------------------------------------------------------------
resource "aws_acm_certificate" "preview_alb" {
  domain_name       = local.preview_wildcard
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 2 証明書とも検証対象は同一ドメイン (*.preview...) のため DNS レコードは同じになる。
# allow_overwrite で衝突を回避し、1 レコードを共有する。
resource "aws_route53_record" "preview_cert_validation" {
  for_each = {
    for o in aws_acm_certificate.preview_cf.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      record = o.resource_record_value
      type   = o.resource_record_type
    }
  }
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  records         = [each.value.record]
  type            = each.value.type
  ttl             = 60
}

resource "aws_acm_certificate_validation" "preview_cf" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.preview_cf.arn
  validation_record_fqdns = [for r in aws_route53_record.preview_cert_validation : r.fqdn]
}

resource "aws_acm_certificate_validation" "preview_alb" {
  certificate_arn         = aws_acm_certificate.preview_alb.arn
  validation_record_fqdns = [for r in aws_route53_record.preview_cert_validation : r.fqdn]
}

# ALB の HTTPS リスナーに preview ワイルドカード証明書を追加（SNI: api.preview...）
resource "aws_lb_listener_certificate" "preview" {
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate_validation.preview_alb.certificate_arn
}

# ---------------------------------------------------------------------
# 共有 API オリジン: api.preview.<domain> → ALB（全 PR の CloudFront が /api でここを指す）
# ---------------------------------------------------------------------
resource "aws_route53_record" "preview_api_origin" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.preview_api_origin
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# frontend バケットは PR ごとに pr-env が作る（terraform/pr-env/main.tf）。
# destroy でバケットごと中身も消えるよう per-PR にした。共有バケットは持たない。

# ---------------------------------------------------------------------
# WAF Web ACL（Basic 認証） — CLOUDFRONT scope（us-east-1）
# 各 PR の CloudFront に関連付ける。Authorization が一致しなければ 401 を返す。
# 資格情報は手動作成の SSM パラメータから生の "user:pass" 形式で読む（コードに直書きしない）。
# base64 化は WAF 側で base64encode() する（SSM には人間が入力する生の値を置く）。
# ---------------------------------------------------------------------
data "aws_ssm_parameter" "preview_basic_auth" {
  name            = "${var.parameter_store_path}preview_basic_auth"
  with_decryption = true
}

# preview の DB ユーザー(preview)のパスワード。手動作成の SSM パラメータ。
# 共有実行ロールがこの ARN を読めるよう ecs_execution_ssm_policy に追加済み。
data "aws_ssm_parameter" "preview_db_password" {
  name            = "${var.parameter_store_path}preview_db_password"
  with_decryption = true
}

resource "aws_wafv2_web_acl" "preview_basic_auth" {
  provider = aws.us_east_1
  name     = "${var.project_name}-preview-basic-auth"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  custom_response_body {
    key          = "unauthorized"
    content      = "Authentication required."
    content_type = "TEXT_PLAIN"
  }

  rule {
    name     = "require-basic-auth"
    priority = 0

    # Authorization ヘッダが「Basic <b64>」と完全一致しない場合に block(401)。
    statement {
      not_statement {
        statement {
          byte_match_statement {
            field_to_match {
              single_header { name = "authorization" }
            }
            positional_constraint = "EXACTLY"
            search_string         = "Basic ${base64encode(data.aws_ssm_parameter.preview_basic_auth.value)}"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    action {
      block {
        custom_response {
          response_code            = 401
          custom_response_body_key = "unauthorized"
          response_header {
            name  = "WWW-Authenticate"
            value = "Basic realm=\"preview\""
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-preview-basic-auth"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-preview-waf"
    sampled_requests_enabled   = true
  }
}

# preview デプロイ用 OIDC ロール（GitHub Environment `preview` 経由でのみ AssumeRole 可）
module "gha_preview_deploy_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role"

  name            = "${var.project_name}-gha-preview-deploy-role"
  use_name_prefix = false

  enable_github_oidc = true
  oidc_subjects      = [local.preview_oidc_sub]

  policies = {
    PreviewDeploy = aws_iam_policy.preview_deploy.arn
  }
}

# ---------------------------------------------------------------------
# preview デプロイ用 IAM ポリシー（GitHub Actions が AssumeRole して Terraform 実行）
# 注意: これは「最小権限の初期案」。CloudFront / ELBv2 など resource-level 非対応 API は
#       Resource="*" になる。IAM だけは /preview/ パス + Boundary 必須で昇格を防ぐ。
#       実運用では terraform plan/apply の AccessDenied を見て継続的に絞り込む。
# ---------------------------------------------------------------------
resource "aws_iam_policy" "preview_deploy" {
  name        = "${var.project_name}-gha-preview-deploy-policy"
  description = "GitHub Actions: provision/destroy per-PR preview environments"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudFront"
        Effect   = "Allow"
        Action   = ["cloudfront:*"]
        Resource = "*"
      },
      {
        Sid      = "Elbv2"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Sid      = "Ecs"
        Effect   = "Allow"
        Action   = ["ecs:*"]
        Resource = "*"
        Condition = {
          # クラスタ単位に縛れる API はこの条件が効く（縛れない API は無視される）。
          ArnEqualsIfExists = { "ecs:cluster" = aws_ecs_cluster.main.arn }
        }
      },
      {
        Sid      = "Sqs"
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = "arn:aws:sqs:ap-northeast-1:${data.aws_caller_identity.current.account_id}:${var.project_name}-preview-pr*"
      },
      {
        Sid      = "Route53Change"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets", "route53:GetHostedZone"]
        Resource = "arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"
      },
      {
        Sid      = "Route53Get"
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "*"
      },
      {
        # PR ごとの frontend バケットを作成/削除/操作する（命名は <project>-preview-pr*）。
        # 範囲を preview-pr* バケットに限定したうえで s3:* を許可（作成/ポリシー/アップロード一式）。
        Sid      = "S3PreviewBuckets"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["arn:aws:s3:::${var.project_name}-preview-pr*", "arn:aws:s3:::${var.project_name}-preview-pr*/*"]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:TagResource", "logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${var.project_name}-preview-pr*"
      },
      {
        Sid      = "AcmWafRead"
        Effect   = "Allow"
        Action   = ["acm:DescribeCertificate", "acm:ListCertificates", "wafv2:GetWebACL", "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL", "wafv2:ListResourcesForWebACL"]
        Resource = "*"
      },
      # --- IAM: /preview/ 配下のみ。CreateRole は Boundary 付与を強制（権限昇格防止）---
      {
        Sid      = "IamCreatePreviewRolesWithBoundary"
        Effect   = "Allow"
        Action   = ["iam:CreateRole", "iam:TagRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/preview/*"
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.preview_boundary.arn }
        }
      },
      {
        Sid    = "IamManagePreviewRoles"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole", "iam:GetRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListInstanceProfilesForRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/preview/*"
      },
      {
        Sid      = "IamPassPreviewRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/preview/*"
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      # 共有の実行ロール（ECR pull / SSM 読み取り）も ECS に渡す
      {
        Sid      = "IamPassExecutionRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = module.ecs_task_execution_role.arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      # --- pr-env の Terraform state（backend S3）---
      {
        Sid      = "TfstateObject"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.tfstate_bucket}/practice/laravel/preview/*"
      },
      {
        Sid      = "TfstateList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.tfstate_bucket}"
        Condition = {
          StringLike = { "s3:prefix" = ["practice/laravel/preview/*"] }
        }
      },
      # stg state（remote_state で読む）への読み取り
      {
        Sid      = "TfstateReadStg"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.tfstate_bucket}/${var.tfstate_key}"
      },
      # SSM（preview 用シークレット読み取り：preview_db_password / app_key 等）
      {
        Sid      = "SsmRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter${var.parameter_store_path}*"
      }
    ]
  })
}

# ---------------------------------------------------------------------
# Permissions Boundary（per-PR ロールが持てる権限の上限）
# preview デプロイロールが作る per-PR ロールに必須付与する。
# ---------------------------------------------------------------------
resource "aws_iam_policy" "preview_boundary" {
  name        = "${var.project_name}-preview-permissions-boundary"
  description = "Max permissions for per-PR preview task roles"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PreviewRuntimeMax"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
          "sqs:GetQueueAttributes", "sqs:GetQueueUrl",
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
          "logs:CreateLogStream", "logs:PutLogEvents",
          "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"
        ]
        # 上限なので広めだが、per-PR ロール自身のポリシーで更に絞る。
        Resource = "*"
      }
    ]
  })
}
