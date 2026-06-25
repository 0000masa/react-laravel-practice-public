# ---------------------------------------------------------------------
# ALB ターゲットグループ + リスナールール（Host + シークレットで PR を識別）
# ---------------------------------------------------------------------
resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-pr${var.pr_number}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.s.vpc_id
  target_type = "ip"

  health_check {
    path    = "/api/health"
    matcher = "200"
  }
}

resource "aws_lb_listener_rule" "web" {
  listener_arn = local.s.alb_https_listener_arn
  priority     = local.priority

  condition {
    host_header {
      values = [local.subdomain]
    }
  }
  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = [local.s.cloudfront_secret]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
