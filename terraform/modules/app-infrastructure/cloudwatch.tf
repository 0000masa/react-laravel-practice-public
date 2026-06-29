# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "ecs_log" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30 //30日で消す
}

# staging.ERROR または staging.CRITICAL を Lambda に流す
resource "aws_cloudwatch_log_subscription_filter" "laravel_error_critical_to_lambda" {
  name           = "${var.project_name}-laravel-error-to-lambda"
  log_group_name = aws_cloudwatch_log_group.ecs_log.name

  # どちらかを含めばマッチ（OR）
  filter_pattern  = "?${var.app_env}.ERROR ?${var.app_env}.CRITICAL"
  destination_arn = aws_lambda_function.notification_function.arn

  # 権限が先にないと作成に失敗するので依存関係を明示
  depends_on = [aws_lambda_permission.allow_cloudwatch_logs_invoke]
}

# 全ログを S3 へ長期アーカイブするため Firehose に流す。
# filter_pattern は空文字 = 全件マッチ（監査目的で全ログを残す）。
# 上の error/critical → Lambda フィルタとは別物。subscription filter は
# 1ロググループあたりデフォルト最大2本で、これで 2/2（上限内）。
# 設計: docs/monitoring/cloudwatch-logs-s3-archival.md / ADR 0011
resource "aws_cloudwatch_log_subscription_filter" "ecs_log_to_firehose_archive" {
  name            = "${var.project_name}-ecs-log-to-firehose-archive"
  log_group_name  = aws_cloudwatch_log_group.ecs_log.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.logs_archive.arn

  # role_arn が必要な理由（上の Lambda 向けフィルタには無いのに、こちらには有る）:
  #   配信先のタイプで認可方式が違う。
  #   - Lambda 宛て: Lambda 側のリソースベースポリシー(aws_lambda_permission)で
  #     「logs.<region>.amazonaws.com からの呼び出し」を許可する → フィルタに role_arn 不要。
  #   - Firehose/Kinesis 宛て: そうしたリソースベースポリシーが無いため、CloudWatch Logs が
  #     この role を AssumeRole して firehose:PutRecord を実行する → role_arn 必須。
  role_arn = module.cwl_to_firehose_role.arn
}

# --- CloudWatch Alarm (Metric Math) ---
resource "aws_cloudwatch_metric_alarm" "ecs_running_less_than_desired" {
  alarm_name        = "${var.project_name}-ecs-running-less-than-desired"
  alarm_description = "ECS service running tasks is less than desired tasks"

  # expression が 1 になったらアラーム
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1

  evaluation_periods  = 1
  datapoints_to_alarm = 1

  # メトリクス未取得で誤爆しないように（必要なら "breaching" に変える）
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.ecs_task_shortage.arn]
  ok_actions    = [aws_sns_topic.ecs_task_shortage.arn]

  # 現在 RUNNING のタスク数
  metric_query {
    id = "m_running"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "RunningTaskCount"
      dimensions = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.main.name
      }
      period = 60
      stat   = "Minimum"
    }
    return_data = false
  }

  # Desired（目標タスク数）
  metric_query {
    id = "m_desired"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "DesiredTaskCount"
      dimensions = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.main.name
      }
      period = 60
      stat   = "Minimum"
    }
    return_data = false
  }

  # 不足していたら 1、そうでなければ 0
  metric_query {
    id          = "e_shortage"
    expression  = "IF(m_running < m_desired, 1, 0)"
    label       = "running < desired"
    return_data = true
  }
}
