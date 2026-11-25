# Containerised Website on AWS ECS Fargate with Terraform

A website packaged as a Docker image and run on Amazon ECS Fargate behind a load balancer, with the whole environment defined as Terraform code. It is built to be understood: every piece is small, commented and explained, so it works as both a deployable project and a hands-on guide to Docker and ECS.

---

## The Problem It Solves

An application that works on one computer often fails on another: a different operating system, a different tool version, a missing library. Fixing that by logging in to servers and installing things by hand is slow, error-prone and impossible to repeat exactly.

A container solves this by packaging the application with everything it needs into a single unit called an image. The same image behaves identically on a laptop, in testing and in production. Amazon ECS then runs those images for you, keeps the right number of copies alive, and replaces any that fail, with no servers for you to manage.

---

## What It Does

1. The website is built into a Docker image with Nginx.
2. The image is stored in a private registry (Amazon ECR).
3. ECS Fargate starts two copies of the container in two availability zones.
4. A load balancer is the only public entry point. It sends visitors to healthy containers and stops sending to unhealthy ones.
5. If a container fails, the ECS service starts a replacement automatically.
6. Logs go to CloudWatch, and alarms email you when something is wrong.

---

## Architecture

```text
 Visitor
    |  HTTP port 80
    v
 Application Load Balancer (public, two availability zones)
    |  health check on "/" every 30 seconds
    v
 ECS Service (keeps 2 tasks running)
    |
    +--> Task 1 (Nginx container, Fargate)   subnet A
    +--> Task 2 (Nginx container, Fargate)   subnet B
            |
            +--> logs to CloudWatch Logs
            +--> image pulled from Amazon ECR

 CloudWatch alarms (unhealthy tasks, high CPU) --> SNS --> Email
```

---

## Docker in Plain Words

| Term | Meaning |
|---|---|
| Image | A read-only package holding the app and everything it needs. Built from a Dockerfile |
| Container | A running copy of an image. Many containers can start from one image |
| Dockerfile | The recipe for building an image, one instruction per line |
| Registry | Storage for images. Here it is Amazon ECR |
| Tag | A label for an image version, such as `v1` |

The Dockerfile in this project is three lines:

```dockerfile
FROM nginx:1.27-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

It starts from a small official Nginx image, copies the website file into it, and documents that the container listens on port 80.

### Why use Docker

- The app runs the same way everywhere, so "it works on my machine" stops being an excuse.
- A new version is a new image, and rolling back means running the previous one.
- Containers start in seconds and many can run side by side.
- The image is an exact, versioned record of what is running.

### Situations where a client needs this

- An app depends on specific software versions and keeps breaking when moved between environments.
- A site must handle traffic spikes and needs several identical copies running at once.
- A company wants releases that are repeatable and easy to roll back.
- A business wants to stop patching and maintaining servers by hand.

---

## Docker, ECS and Kubernetes

These are not competitors at the same level.

| Tool | Role |
|---|---|
| Docker | Builds images and runs containers |
| ECS | An AWS service that runs containers at scale, keeps them healthy and connects them to a load balancer |
| Kubernetes (EKS on AWS) | A more powerful and more complex system for the same job, common in large teams and across multiple clouds |

Docker packages the app and ECS runs the packages. ECS is a sensible first choice on AWS because it is simpler than Kubernetes and works directly with IAM, CloudWatch and load balancers. Kubernetes makes sense when a team needs its portability or ecosystem and can afford the extra complexity.

### Why Fargate

With Fargate, AWS supplies the compute for each container. There are no EC2 instances to patch or scale, and billing covers only the CPU and memory the tasks use while they run.

---

## ECS Concepts and Where to Find Them

| Concept | What it does | File |
|---|---|---|
| ECR repository | Stores the images. Tags are immutable, so `v1` always means the same image. Images are scanned on push and only the newest 5 are kept | `ecr.tf` |
| Cluster | A logical group that services run in | `ecs.tf` |
| Task definition | The recipe for a task: image, CPU, memory, port and log destination | `ecs.tf` |
| Task | One running copy of the task definition | created by the service |
| Service | Keeps the desired number of tasks running, replaces failed ones and rolls out new versions | `ecs.tf` |
| Load balancer and target group | The public entry point. Spreads traffic and only sends it to healthy tasks. Target type is `ip`, which Fargate requires | `alb.tf` |
| Health check | Requests `/` regularly. A task that keeps failing is removed and replaced | `alb.tf` |
| Execution role | Lets ECS itself pull the image and write logs | `iam.tf` |
| Task role | Permissions for the application code. Empty here on purpose, because a static site needs none | `iam.tf` |
| Networking and security groups | `awsvpc` mode gives each task its own network interface. Tasks accept traffic only from the load balancer | `network.tf` |
| Logging | Container output goes to CloudWatch Logs and is kept for 14 days | `ecs.tf` |
| Alarms | Email alerts for unhealthy tasks and high CPU | `monitoring.tf` |
| Deployment circuit breaker | If a new version keeps failing, the rollout stops and rolls back | `ecs.tf` |

---

## Design Decisions

| Choice | Why |
|---|---|
| Fargate instead of EC2 | No servers to manage or patch |
| Tasks in public subnets with public IPs | Avoids a NAT Gateway, which costs money every hour. The security group still blocks all direct access, so only the load balancer can reach the containers |
| Two availability zones, two tasks | The site stays up if one zone or one task fails |
| Immutable image tags | A tag cannot be silently replaced, so what is running is always traceable |
| Pinned base image (`nginx:1.27-alpine`) | Builds are predictable and Alpine keeps the image small |
| Separate execution and task roles | Each role has only the permissions it needs |
| Remote Terraform state in S3 | State is not tied to one computer |
| CI with no AWS credentials | The pipeline can check the code safely without access to the account |

---

## Project Structure

```text
terraform-ecs-fargate-website/
├── .github/workflows/terraform-ci.yml   # Runs fmt and validate on every pull request
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

## Try the Container Locally

Before any AWS, run the same image on your own computer:

```bash
docker build -t ecs-website ./app
docker run -d -p 8081:80 --name web ecs-website
```

Open `http://localhost:8081`. Useful commands:

```bash
docker ps              # running containers
docker logs web        # what Nginx has printed
docker stop web        # stop it
docker rm web          # remove it
```

Port 8081 is used on the host because 8080 is often taken by other tools.

---

## Deployment

Prerequisites: an AWS account with the AWS CLI configured, Terraform `>= 1.0.0`, Docker, and an S3 bucket for remote state (set in `providers.tf`).

Create `terraform/terraform.tfvars` (ignored by Git):

```hcl
alert_email = "you@example.com"
```

The service cannot start until the image exists in ECR, so the deployment has to follow this order. Run everything from the `terraform/` folder.

**1. Initialise and check the code**

```bash
terraform init
terraform fmt
terraform validate
```

**2. Create only the image repository**

```bash
terraform apply -target=aws_ecr_repository.app
```

Terraform warns that `-target` is not meant for routine use. Here it is deliberate: the repository has to exist before an image can be pushed to it.

**3. Build and push the image**

```bash
REPO=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${REPO%%/*}
docker build --platform linux/amd64 -t $REPO:v1 ../app
docker push $REPO:v1
```

`--platform linux/amd64` makes the image match the architecture the task is set to run, which matters when building on an ARM computer.

**4. Create everything else**

```bash
terraform plan
terraform apply
```

**5. Finish**

Click **Confirm subscription** in the email AWS sends. Wait one to two minutes for the tasks to pass their health checks, then open the `website_url` output.

### Tear down

```bash
terraform destroy
```

The ECR repository is set to delete its images, so nothing is left behind and billing stops.

---

## Continuous Integration

A GitHub Actions workflow (`.github/workflows/terraform-ci.yml`) runs on every pull request and every push to `main`:

1. `terraform fmt -check` fails if the code is not formatted.
2. `terraform init -backend=false` sets up the providers without touching the remote state.
3. `terraform validate` checks that the configuration is valid.

It uses no AWS credentials, so it cannot change anything in the account. Changes are made on a feature branch, checked by this workflow in a pull request, and merged only when it passes. Building the image and deploying are still done by hand.

---

## Things to Try

These experiments are the quickest way to understand ECS.

- **Self-healing.** In the ECS console, stop one task. The service notices and starts a replacement, and the site stays up because the other task keeps serving.
- **Read the logs.** Open CloudWatch Logs, group `/ecs/ecs-website`, and find the request lines from your own visits.
- **Ship a new version.** Edit `index.html`, build and push the image as `v2`, set `image_tag = "v2"`, and apply. The service starts new tasks and retires the old ones.
- **Break a release on purpose.** Set `image_tag` to a tag that does not exist. The circuit breaker stops the rollout and keeps the working version running.
- **Check the security group.** Try opening a task's public IP directly. It does not respond, because only the load balancer is allowed in.

---

## Docker Do's and Don'ts

**Do**

- Pin image versions (`nginx:1.27-alpine`) so builds are repeatable.
- Use small base images such as Alpine.
- Tag images with a version or the git commit, and never overwrite a tag.
- Write logs to standard output so Docker and CloudWatch can collect them.
- Use a `.dockerignore` file to keep junk and secrets out of the build.
- Run one main process per container.
- Scan images for vulnerabilities. ECR does this on every push here.
- Keep images small, because they build, push and start faster.

**Don't**

- Don't use the `latest` tag in production. You cannot tell which version is running.
- Don't put secrets, passwords or keys inside an image. Anyone with the image can read them. Pass them in at run time from a secrets service.
- Don't run containers as root when you can avoid it.
- Don't store important data inside a container. It disappears when the container is replaced.
- Don't log in to a running container to fix things by hand. Change the image and redeploy.
- Don't install tools you do not need. Each one makes the image larger and widens the attack surface.
- Don't copy the whole project folder into the image without a `.dockerignore`.

---

## Troubleshooting

| Problem | Likely cause and fix |
|---|---|
| `503` from the load balancer right after deploying | Tasks are still starting or have not passed health checks. Wait a minute or two and refresh |
| Tasks keep stopping and restarting | Check the service Events tab and the CloudWatch logs. A missing image tag or an architecture mismatch are common causes |
| Service cannot pull the image | The tag in `image_tag` does not exist in ECR, or the image was never pushed |
| `exec format error` in the logs | The image was built for a different CPU architecture. Rebuild with `--platform linux/amd64` |
| Port already in use when running locally | Another program owns the port. Change the left side of `-p`, for example `-p 8081:80` |
| No alarm emails | The SNS subscription has not been confirmed. Click the link in the AWS email |
| `terraform apply` fails on the service in a fresh account | The repository has no image yet. Follow the deployment order above |

---

## Things to Know

- **It costs money while it runs.** The load balancer and the Fargate tasks are billed by the hour. Destroy the stack when you are not using it.
- **Plain HTTP only.** There is no HTTPS or custom domain. A real site would add an ACM certificate and an HTTPS listener.
- **Confirm the alert email.** No alarm emails arrive until you click the confirmation link.
- **First start is not instant.** Tasks need a minute or two to start and pass health checks.
- **Checks run automatically, deploys do not.** CI validates the Terraform code, but building the image and deploying it are manual steps.
- **Public IPs on tasks.** This is a cost trade-off. A production setup would usually place tasks in private subnets behind NAT or VPC endpoints.

---

## Ideas for Extending It

- Extend the CI pipeline to build the image, push it to ECR and update the service, using GitHub Actions OIDC so no AWS keys are stored
- HTTPS with an ACM certificate and a custom domain on Route 53
- Auto scaling of the service on CPU or request count
- Private subnets with VPC endpoints instead of public IPs
- A CloudWatch dashboard for requests, latency and task counts
- A second service that adds a small backend API