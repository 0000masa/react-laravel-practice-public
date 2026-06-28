# ---------------------------------------------------------------------
# per-PR タスクロール（/preview/ パス + Permissions Boundary 必須）
# 実行ロール(ECR pull / SSM)は stg の共有ロールを再利用する。
# ---------------------------------------------------------------------
# このロールは GitHub Actions の preview デプロイロールが iam:CreateRole で作る。
# そのデプロイ権限（stg/preview_shared.tf の IamCreatePreviewRolesWithBoundary）は
# 2 ゲートを課しており、以下の 2 行がそれを満たすために必須:
#   - path = "/preview/"            → ロール ARN を role/preview/* にして
#                                      Resource ゲート（role/preview/* のみ作成可）を通過。
#   - permissions_boundary = ...      → Condition ゲート（Boundary 付与の強制）を通過。
# どちらを欠いても CreateRole は AccessDenied になる（ADR 0006）。
# Boundary は天井（最大権限）。このロールの実効権限は、下の自前ポリシー
# （aws_iam_role_policy.task）と Boundary の積集合になる。
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
        # メール送信。From は stg の検証済み SES アイデンティティ（locals.tf の
        # MAIL_FROM_ADDRESS）。Resource をその identity ARN に絞る。
        # 注: 実効権限は Boundary(PreviewRuntimeMax) との積集合。Boundary 側にも
        # ses:SendEmail/SendRawEmail が必要（stg/preview_shared.tf）。
        Sid      = "SesSend"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = local.s.ses_domain_identity_arn
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
