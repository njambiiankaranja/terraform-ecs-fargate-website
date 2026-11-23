# The Application Load Balancer: the public front door of the website.
# It sends each visitor to a healthy task and stops sending to unhealthy ones.

resource "aws_lb" "web" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

# The target group is the list of tasks the load balancer sends traffic to.
# target_type "ip" is required for Fargate tasks.
resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  # Drain old tasks quickly when they are replaced or removed
  deregistration_delay = 30

  # The health check: every 30 seconds the load balancer requests "/".
  # A task that keeps failing is taken out and replaced by the service.
  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}