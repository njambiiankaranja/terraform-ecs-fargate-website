# Containerised Website on AWS ECS Fargate with Terraform

A static website packaged as a Docker image and run on Amazon ECS Fargate behind a load balancer, with everything defined as Terraform code. This project is also a worked example for learning Docker and ECS: each part of the setup is explained, and the deployment is small enough to understand end to end.

---

## The Problem It Solves

A website that works on one computer often breaks on another: a different operating system, a different version of a tool, a missing library. Fixing this by logging in to servers and installing things by hand is slow and cannot be repeated reliably.

Containers solve this by packaging the application together with everything it needs into one unit called an image. The same image runs identically on a laptop, a test server or in production. ECS is the AWS service that runs those images for you, keeps them alive, and replaces them if they fail, without you managing any servers.

---

## Docker in Plain Words

| Term | Meaning |
|---|---|
| Image | A read-only package containing the app and everything it needs. Built from a Dockerfile |
| Container | A running copy of an image. You can start many from one image |
| Dockerfile | The recipe for building an image, line by line |
| Registry | A storage place for images. Here it is Amazon ECR |
| Tag | A label on an image version, such as `v1` |

The Dockerfile in this project is three lines:

```dockerfile
FROM nginx:1.27-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

It starts from a small official Nginx image, copies the website file into it, and documents that the container listens on port 80.

### Why use Docker at all

- The app runs the same way everywhere, so "it works on my machine" stops being a problem.
- A new version is a new image. Rolling back means running the previous image.
- Starting a container takes seconds, and many copies can run side by side.
- The image is a precise, versioned description of what is running.

### Scenarios where a client would need this

- A team has an app that depends on specific software versions and keeps breaking when moved between environments.
- A site must handle traffic spikes and needs several identical copies running at once.
- A company wants releases that are repeatable and easy to roll back.
- A business wants to stop maintaining and patching servers by hand.

---

## Docker, ECS and Kubernetes

These are not competitors at the same level.

| | What it is |
|---|---|
| Docker | The tool that builds images and runs containers |
| ECS | An AWS service that runs containers at scale, keeps them healthy and connects them to a load balancer |
| Kubernetes (EKS on AWS) | A more powerful and more complex system for the same job, used across many clouds and large teams |

You use Docker to package the app, and ECS to run the packages. ECS is a good first choice on AWS because it is simpler than Kubernetes and integrates directly with IAM, CloudWatch and load balancers. Kubernetes makes sense when a team needs its portability or ecosystem and can afford the extra complexity.

### Why ECS Fargate here

With Fargate, AWS provides the compute for each container. There are no EC2 instances to patch or scale, and you pay only for the CPU and memory the tasks use while they run.

---

## What It Builds

```text
 Visitor
    |  HTTP port 80
    v
 Application Load Balancer (public, two availability zones)
    |  health check on "/" every 30 seconds
    v
 ECS Service (keeps 2 tasks running)
    |
    +--> Task 1 (Nginx container, Fargate)   in subnet A
    +--> Task 2 (Nginx container, Fargate)   in subnet B
            |
            +--> logs to CloudWatch Logs
            +--> image pulled from Amazon ECR

 CloudWatch alarms (unhealthy tasks, high CPU) --> SNS --> Email
```

---

## ECS Concepts and Where to Find Them

| Concept | What it does | File |
|---|---|---|
| ECR repository | Stores the Docker images. Tags are immutable, so `v1` always means the same image. Images are scanned on push and only the newest 5 are kept | `ecr.tf` |
| Cluster | A logical group that your services run in | `ecs.tf` |
| Task definition | The recipe for a task: which image, CPU, memory, port and where logs go | `ecs.tf` |
| Task | One running copy of the task definition | created by the service |
| Service | Keeps the desired number of tasks running, replaces failed ones, and handles new releases | `ecs.tf` |
| Load balancer and target group | Public entry point that spreads traffic and only sends it to healthy tasks. Target type is `ip`, which Fargate requires | `alb.tf` |
| Health check | Requests `/` regularly. A task that keeps failing is removed and replaced | `alb.tf` |
| Execution role | Lets ECS itself pull the image and write logs | `iam.tf` |
| Task role | Permissions for the application code. Empty here on purpose, because a static site needs none | `iam.tf` |
| Networking and security groups | `awsvpc` mode gives each task its own network interface. The tasks accept traffic only from the load balancer | `network.tf` |
| Logging | Container output goes to CloudWatch Logs, kept for 14 days | `ecs.tf` |
| Alarms | Email alerts when a task is unhealthy or CPU is high | `monitoring.tf` |
| Deployment circuit breaker | If a new version keeps failing, the rollout stops and rolls back automatically | `ecs.tf` |

---

## Design Decisions

| Choice | Why |
|---|---|
| Fargate instead of EC2 | No servers to manage or patch |
| Tasks in public subnets with public IPs | Avoids a NAT Gateway, which costs money every hour. The security group still blocks all direct access, so only the load balancer can reach the containers |
| Two availability zones, two tasks | The site stays up if one zone or one task fails |
| Immutable image tags | A tag cannot be silently changed, so what is running is always traceable |
| Pinned base image (`nginx:1.27-alpine`) | Builds are predictable, and Alpine keeps the image small |
| Separate execution and task roles | Each has only the permissions it needs |
| Remote Terraform state in S3 | State is not tied to one computer |

---

## Project Structure

```text
terraform-ecs-fargate-website/
├── app/
│   ├── Dockerfile       # How the image is built
│   ├── .dockerignore    # Files kept out of the image
│   └── index.html       # The website
├── terraform/
│   ├── providers.tf     # Provider versions and S3 backend
│   ├── variables.tf     # Inputs and defaults
│   ├── network.tf       # VPC, subnets, security groups
│   ├── ecr.tf           # Image repository
│   ├── iam.tf           # Execution and task roles
│   ├── alb.tf           # Load balancer, target group, listener
│   ├── ecs.tf           # Cluster, task definition, service, log group
│   ├── monitoring.tf    # SNS topic and CloudWatch alarms
│   └── outputs.tf       # Website URL and resource names
├── .gitignore
└── README.md
```

### Variables

| Variable | Default | Description |
|---|---|---|
| `alert_email` | none, required | Address that receives alarm emails |
| `aws_region` | `us-east-1` | Region to deploy into |
| `project_name` | `ecs-website` | Prefix for resource names |
| `image_tag` | `v1` | Which image tag the service runs |
| `desired_count` | `2` | Number of tasks to keep running |
| `task_cpu` / `task_memory` | `256` / `512` | Size of each task |
| `cpu_alarm_threshold` | `70` | CPU percentage that triggers the alarm |
| `container_port` | `80` | Port the container listens on |
| `vpc_cidr` / `public_subnet_cidrs` | `10.0.0.0/16` / two `/24` blocks | Network ranges |

---

## Deployment

Prerequisites: an AWS account with the AWS CLI configured, Terraform `>= 1.0.0`, Docker, and an S3 bucket for remote state (set in `providers.tf`).

Create `terraform/terraform.tfvars` (ignored by Git):

```hcl
alert_email = "you@example.com"
```

The service needs the image to exist before it can start, so deploy in this order. Run these from the `terraform/` folder.

**1. Initialise and check the code**

```bash
terraform init
terraform fmt
terraform validate
```

**2. Create the image repository first**

```bash
terraform apply -target=aws_ecr_repository.app
```

Terraform warns that `-target` is not for routine use. Here it is deliberate, because the repository must exist before an image can be pushed.

**3. Build and push the image**

```bash
REPO=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${REPO%%/*}
docker build --platform linux/amd64 -t $REPO:v1 ../app
docker push $REPO:v1
```

`--platform linux/amd64` makes the image match the task's CPU architecture, which matters when building on an ARM computer.

**4. Create everything else**

```bash
terraform plan
terraform apply
```

**5. Finish**

Click **Confirm subscription** in the email AWS sends. Wait one to two minutes for the tasks to pass their health checks, then open the `website_url` output.

### Try it locally first

```bash
docker build -t ecs-website ./app
docker run -d -p 8081:80 --name web ecs-website
```

Open `http://localhost:8081`. Use `docker logs web` to see Nginx's output, then `docker stop web` and `docker rm web` to clean up.

---

## Things to Try

These experiments are the quickest way to understand ECS.

- **Self-healing.** In the ECS console, stop one task. The service notices and starts a replacement. The site stays up the whole time because the other task keeps serving.
- **Read the logs.** Open CloudWatch Logs, group `/ecs/ecs-website`, and find the request log lines from your own visits.
- **Ship a new version.** Edit `index.html`, build and push the image as `v2`, set `image_tag = "v2"`, and apply. Watch the service start new tasks and retire the old ones.
- **Break a release on purpose.** Set `image_tag` to a tag that does not exist. The circuit breaker stops the rollout and keeps the working version running.
- **Check the security group.** Try opening a task's public IP directly. It does not respond, because only the load balancer is allowed in.

---

## Docker Do's and Don'ts

**Do**

- Pin image versions (`nginx:1.27-alpine`), so builds are repeatable.
- Use small base images such as Alpine.
- Tag images with a version or the git commit, and never overwrite a tag.
- Write logs to standard output, so Docker and CloudWatch can collect them.
- Use a `.dockerignore` file to keep junk and secrets out of the build.
- Run one main process per container.
- Scan images for vulnerabilities (ECR does this on push here).
- Keep images small, because they build, push and start faster.

**Don't**

- Don't use the `latest` tag in production. You cannot tell which version is running.
- Don't put secrets, passwords or keys inside an image. Anyone with the image can read them. Use environment variables from a secrets service instead.
- Don't run containers as root when you can avoid it.
- Don't store important data inside a container. It disappears when the container is replaced.
- Don't log in to a running container to fix things by hand. Change the image and redeploy.
- Don't install extra tools you do not need. Every addition makes the image larger and widens the attack surface.
- Don't copy the whole project folder into the image without a `.dockerignore`.

---

## Things to Know

- **It costs money while it runs.** The load balancer and the Fargate tasks are billed by the hour. Destroy the stack when you are not using it.
- **Plain HTTP only.** There is no HTTPS or custom domain. A real site would add an ACM certificate and an HTTPS listener.
- **Confirm the alert email.** No alarm emails arrive until you click the confirmation link.
- **First start is not instant.** Tasks need a minute or two to start and pass health checks.
- **Deploys happen from your computer.** Image builds and pushes are manual here. Automating them is the natural next step.
- **Public IPs on tasks.** This is a cost trade-off. A production setup would usually place tasks in private subnets behind NAT or VPC endpoints.

---

## Tear Down

```bash
terraform destroy
```

The ECR repository is set to delete its images on destroy, so nothing is left behind and billing stops.

---

## Ideas for Extending It

- A GitHub Actions pipeline that builds the image, pushes it to ECR and updates the service, using OIDC so no AWS keys are stored
- HTTPS with an ACM certificate and a custom domain on Route 53
- Auto scaling of the service on CPU or request count
- Private subnets with VPC endpoints instead of public IPs
- A CloudWatch dashboard for requests, latency and task counts
- A second service that adds a small backend API