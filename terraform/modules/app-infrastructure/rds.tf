# RDS本体
resource "aws_db_instance" "main" {
  identifier                      = "${var.project_name}-db"
  engine                          = "mariadb"
  engine_version                  = "11.4" # ←ここを11.4系に固定
  instance_class                  = var.rds_config.instance_class
  allocated_storage               = 20
  storage_type                    = "gp3"
  db_name                         = var.db_name
  username                        = var.db_username # variables.tfで定義した変数を参照
  password                        = data.aws_ssm_parameter.db_password.value
  db_subnet_group_name            = aws_db_subnet_group.main.name
  vpc_security_group_ids          = [aws_security_group.rds_sg.id]
  skip_final_snapshot             = var.rds_config.skip_final_snapshot
  publicly_accessible             = false
  storage_encrypted               = true
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = var.rds_config.enabled_cloudwatch_logs_exports
  maintenance_window              = "sun:15:00-sun:15:30" # UTC。JST では 月曜 00:00-00:30（UTC+9）

  # Multi-AZ 構成（スタンバイDBを別AZに自動配置、障害時は1〜2分で自動フェイルオーバー）
  multi_az = var.rds_config.multi_az

  # 自動バックアップ（最大35日、PITR有効化の前提）
  backup_retention_period = var.rds_config.backup_retention_period
  backup_window           = "17:00-17:30" # UTC。JST 02:00-02:30（メンテナンスウィンドウと被らないように）

  # Performance Insights（直近7日間は無料）
  performance_insights_enabled = var.rds_config.performance_insights_enabled

  # Enhanced Monitoring（OS層メトリクスをCloudWatch Logsへ送信。0で無効）
  monitoring_interval = var.rds_config.monitoring_interval
  monitoring_role_arn = var.rds_config.monitoring_interval > 0 ? module.rds_enhanced_monitoring_role.arn : null

  # DBの変更をすぐに反映させるか
  apply_immediately = var.rds_config.apply_immediately

  tags = {
    Name = "${var.project_name}-db"
  }
}

#DBサブネットグループ
resource "aws_db_subnet_group" "main" {
  name = "${var.project_name}-db-subnet-group"
  subnet_ids = [
    local.private_subnet_a_id,
    local.private_subnet_c_id
  ]
  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}
