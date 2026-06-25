# ---------------------------------------------------------------------
# SQS（QR 非同期。PR ごとに分離）
# ---------------------------------------------------------------------
resource "aws_sqs_queue" "qrcode" {
  name                       = local.queue_name
  visibility_timeout_seconds = 90
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
}
