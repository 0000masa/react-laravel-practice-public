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
