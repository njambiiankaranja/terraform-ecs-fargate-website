variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy into"
}

variable "project_name" {
  type        = string
  default     = "ecs-website"
  description = "Prefix for resource names and the Project tag"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for the public subnets, one per availability zone (a load balancer needs at least two)"
}

variable "container_port" {
  type        = number
  default     = 80
  description = "Port the container listens on (Nginx uses 80)"
}

variable "task_cpu" {
  type        = number
  default     = 256
  description = "CPU units for each task (256 = 0.25 vCPU)"
}

variable "task_memory" {
  type        = number
  default     = 512
  description = "Memory in MB for each task"
}

variable "desired_count" {
  type        = number
  default     = 2
  description = "How many copies of the container the service keeps running"
}

variable "image_tag" {
  type        = string
  default     = "v1"
  description = "Tag of the Docker image to run. Use a new tag for every version"
}

variable "cpu_alarm_threshold" {
  type        = number
  default     = 70
  description = "Average CPU percentage that triggers the high CPU alarm"

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be between 1 and 100."
  }
}

variable "alert_email" {
  type        = string
  description = "Email address that receives alarm notifications"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}