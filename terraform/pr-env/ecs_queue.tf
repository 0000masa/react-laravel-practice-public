# ---------------------------------------------------------------------
# queue-worker（QR 非同期。PR ごとに分離）
# ---------------------------------------------------------------------
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
