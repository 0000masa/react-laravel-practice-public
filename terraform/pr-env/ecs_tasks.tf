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
