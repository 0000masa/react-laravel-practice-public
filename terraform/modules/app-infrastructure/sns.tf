
# --- SNS topic ---
resource "aws_sns_topic" "ecs_task_shortage" {
  name = "${var.project_name}-ecs-task-shortage"
}

# --- SNS subscription (email) ---
resource "aws_sns_topic_subscription" "ecs_task_shortage_email" {
  topic_arn = aws_sns_topic.ecs_task_shortage.arn
  protocol  = "email"
  endpoint  = data.aws_ssm_parameter.alert_email_to.value
}
