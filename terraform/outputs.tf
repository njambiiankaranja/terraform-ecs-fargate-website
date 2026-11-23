output "website_url" {
  description = "Public address of the website (the load balancer)"
  value       = "http://${aws_lb.web.dns_name}"
}

output "ecr_repository_url" {
  description = "Where to push the Docker image"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.web.name
}