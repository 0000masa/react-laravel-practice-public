# ---------------------------------------------------------------------
# ログアーカイブ用 Firehose 配信ストリーム
# CloudWatch Logs（subscription filter）→ Firehose → S3 で長期アーカイブする。
# 設計: docs/monitoring/cloudwatch-logs-s3-archival.md / 方式判断: ADR 0011
#
# 圧縮について:
#   CloudWatch Logs は subscription に gzip 圧縮済みで流すため、ここでは
#   展開(decompression)も Firehose 側の再圧縮もせず、届いたデータをそのまま
#   S3 に置く（compression_format はデフォルト = UNCOMPRESSED）。
#   展開すると取込課金が解凍後バイト基準になり割高なので有効化しない。
# ---------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "logs_archive" {
  name        = "${var.project_name}-logs-archive"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = module.firehose_logs_role.arn
    bucket_arn = aws_s3_bucket.logs_archive.arn

    # 低トラフィックでも 1 オブジェクトを大きくするため時間は最大(900s)。
    # サイズ 64MB は大量時の上限（低トラフィックでは時間側が先に効く）。
    buffering_interval = 900
    buffering_size     = 64

    # 日付パーティション（Athena のスキャン量＝コスト削減）。
    prefix = "app-logs/!{timestamp:yyyy/MM/dd/}"
    # S3 書き込みに失敗したレコードの退避先。
    error_output_prefix = "errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd/}"
  }
}
