# ECR: the private place on AWS where your Docker images are stored

resource "aws_ecr_repository" "app" {
  name = var.project_name

  # Tags cannot be overwritten, so v1 always means the same image
  image_tag_mutability = "IMMUTABLE"

  # Lets "terraform destroy" delete the repository even if it holds images
  force_delete = true

  # Scan every pushed image for known vulnerabilities
  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep only the 5 newest images so old ones do not pile up
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}