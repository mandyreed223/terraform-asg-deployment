# ☁️ Terraform Auto Scaling Web Application on AWS

A highly available AWS web application built with **Terraform**, using an **Application Load Balancer**, **Auto Scaling Group**, private EC2 instances across multiple Availability Zones, secure administration through **AWS Systems Manager Session Manager**, and an encrypted **S3 remote backend** for Terraform state.

This project started as an Auto Scaling deployment and turned into something even more valuable: a real troubleshooting exercise involving failed health checks, cloud-init, user data, Launch Template versions, instance replacement, secure private-instance access, and Terraform state management.

> 🟢 **Green Means GO!**

---

## 🏗️ Architecture

![Terraform ASG Architecture](screenshots/00-terraform-asg-architecture-diagram.png)

### Application Traffic Flow

```text
User
  ↓
ALB DNS Name
  ↓
Application Load Balancer
  ↓
Target Group :80
  ↓
Auto Scaling Group
  ↓
EC2 Apache Web Servers
```

The Application Load Balancer spans two public subnets while the EC2 instances run in private subnets across two Availability Zones.

The EC2 instances have no direct inbound access from the internet.

---

## 🎯 Project Goals

The goal of this project was to build a production-aligned Auto Scaling architecture using Infrastructure as Code while strengthening my understanding of how Terraform resources connect to one another.

The deployment includes:

- Custom VPC
- Two Availability Zones
- Two public subnets
- Two private subnets
- Internet Gateway
- NAT Gateway
- Public and private route tables
- Application Load Balancer
- Target Group with HTTP health checks
- Auto Scaling Group
- EC2 Launch Template
- Apache web servers
- Security group-to-security group access
- IAM instance profile
- AWS Systems Manager Session Manager
- S3 remote Terraform state
- S3 state versioning
- Server-side encryption
- Public access blocking
- Terraform state locking

---

## 🧰 Technologies Used

| Technology | Purpose |
| --- | --- |
| Terraform | Infrastructure as Code |
| AWS VPC | Network isolation and routing |
| Amazon EC2 | Apache web servers |
| EC2 Auto Scaling | Instance health and automatic replacement |
| Application Load Balancer | Distributes incoming web traffic |
| Target Groups | Routes traffic and performs health checks |
| IAM | EC2 instance permissions |
| AWS Systems Manager | Secure EC2 administration without SSH |
| Amazon S3 | Remote Terraform state |
| Amazon Linux 2023 | EC2 operating system |
| Apache HTTP Server | Web application |
| AWS CLI | Deployment verification and troubleshooting |
| PowerShell | Local CLI environment |

---

# 🌐 Network Design

The custom VPC uses:

```text
10.0.0.0/16
```

and spans two Availability Zones in `us-east-1`.

| Subnet | CIDR | Purpose |
| --- | --- | --- |
| Public Subnet 1 | `10.0.1.0/24` | ALB + NAT Gateway |
| Public Subnet 2 | `10.0.2.0/24` | ALB |
| Private Subnet 1 | `10.0.11.0/24` | ASG EC2 instances |
| Private Subnet 2 | `10.0.12.0/24` | ASG EC2 instances |

### Public Traffic

The public subnets use a route to the Internet Gateway:

```text
0.0.0.0/0
      ↓
Internet Gateway
```

The internet-facing Application Load Balancer spans both public subnets.

### Private Instance Outbound Traffic

The EC2 instances do not receive public IP addresses.

A NAT Gateway in **Public Subnet 1** provides outbound internet access for the private subnets:

```text
Private EC2
     ↓
Private Route Table
     ↓
NAT Gateway
     ↓
Public Subnet 1
     ↓
Internet Gateway
     ↓
Internet
```

This allows the private instances to install packages and reach external services without exposing them directly to inbound internet traffic.

---

# 🔐 Security Design

The architecture separates public application access from the EC2 layer using two security groups.

## Application Load Balancer Security Group

```text
Inbound:
TCP 80
Source: 0.0.0.0/0

Outbound:
All traffic
```

## EC2 Security Group

```text
Inbound:
TCP 80
Source: ALB Security Group

Outbound:
All traffic
```

Instead of allowing EC2 port 80 from the entire internet, the EC2 security group references the **ALB security group**.

The resulting path is:

```text
Internet
   ↓
ALB Security Group
   ↓
Application Load Balancer
   ↓
EC2 Security Group
   ↓
Apache
```

Only web traffic coming through the load balancer can reach Apache on the private instances.

---

# 🔗 Terraform Resource Linkage

One of my main goals with this project was strengthening my understanding of how Terraform resources pass values to one another.

For example:

```hcl
resource "aws_security_group" "ec2" {
  vpc_id = aws_vpc.main.id
}
```

Terraform creates:

```text
aws_vpc.main
```

AWS assigns the VPC an actual ID:

```text
vpc-xxxxxxxx
```

Terraform exposes that value through:

```hcl
aws_vpc.main.id
```

and passes it into the security group.

This same pattern connects the architecture together.

### VPC → Subnets

```hcl
vpc_id = aws_vpc.main.id
```

### VPC → Security Groups

```hcl
vpc_id = aws_vpc.main.id
```

### NAT Gateway → Public Subnet

```hcl
subnet_id = aws_subnet.public_a.id
```

### Private Route → NAT Gateway

```hcl
nat_gateway_id = aws_nat_gateway.main.id
```

### EC2 Security Group → ALB Security Group

```hcl
security_groups = [aws_security_group.alb.id]
```

### ALB → Public Subnets

```hcl
subnets = [
  aws_subnet.public_a.id,
  aws_subnet.public_b.id
]
```

### Target Group → VPC

```hcl
vpc_id = aws_vpc.main.id
```

### Listener → ALB

```hcl
load_balancer_arn = aws_lb.web.arn
```

### Listener → Target Group

```hcl
target_group_arn = aws_lb_target_group.web.arn
```

### Auto Scaling Group → Private Subnets

```hcl
vpc_zone_identifier = [
  aws_subnet.private_a.id,
  aws_subnet.private_b.id
]
```

### Auto Scaling Group → Target Group

```hcl
target_group_arns = [
  aws_lb_target_group.web.arn
]
```

### Auto Scaling Group → Launch Template

```hcl
launch_template {
  id      = aws_launch_template.web.id
  version = "$Latest"
}
```

### Launch Template → EC2 Security Group

```hcl
vpc_security_group_ids = [
  aws_security_group.ec2.id
]
```

### IAM Role → Instance Profile

```hcl
role = aws_iam_role.ec2_ssm.name
```

### Instance Profile → Launch Template

```hcl
iam_instance_profile {
  name = aws_iam_instance_profile.ec2_ssm.name
}
```

These references also create **implicit dependencies**, allowing Terraform to determine much of the correct resource creation order automatically.

---

# 🚀 Launch Template & Auto Scaling

The EC2 configuration is defined through an AWS Launch Template.

The template specifies:

- Amazon Linux 2023
- `t3.micro`
- EC2 security group
- IAM instance profile
- Apache bootstrap script

The Auto Scaling Group uses:

```text
Minimum: 2
Desired: 2
Maximum: 5
```

and launches instances across both private subnets.

This maintains two instances during normal operation while allowing the group to scale as high as five instances.

![Healthy Auto Scaling instances](screenshots/02-asg-healthy-multi-az-instances.png)

---

# 📜 Bootstrapping Apache with User Data

The final configuration keeps the operating system bootstrap logic in a separate file:

```text
user_data.sh
```

The Launch Template loads the script using:

```hcl
user_data = base64encode(file("${path.module}/user_data.sh"))
```

The script installs Apache, enables the service, starts it, and creates the project landing page.

Separating the bootstrap script from `main.tf` keeps the Terraform configuration cleaner and makes the user data easier to inspect and troubleshoot.

---

# 🔎 Troubleshooting Story

This became one of the most valuable parts of the project.

After the initial deployment, Terraform completed successfully and the Auto Scaling Group launched EC2 instances.

But the Application Load Balancer Target Group reported:

```text
unhealthy
Target.FailedHealthChecks
```

Terraform had successfully created the infrastructure, but something in the application path wasn't working.

Rather than immediately changing resources, I followed the request path layer by layer.

---

## 1️⃣ Follow the Request Path

The expected path was:

```text
Browser
   ↓
Application Load Balancer
   ↓
ALB Security Group
   ↓
Target Group
   ↓
EC2 Security Group
   ↓
Apache
```

The EC2 security group correctly allowed TCP port 80 from the ALB security group.

The instances were also being launched into the expected private subnets.

That eliminated several possible causes.

---

## 2️⃣ Verify the Outbound Network Path

Because the instances needed outbound internet access to install Apache, I verified:

```text
Private Subnet
      ↓
Private Route Table
      ↓
NAT Gateway
      ↓
Public Subnet
      ↓
Internet Gateway
```

The NAT Gateway was available.

The private route table contained:

```text
0.0.0.0/0
      ↓
NAT Gateway
```

and the public route table contained:

```text
0.0.0.0/0
      ↓
Internet Gateway
```

The outbound network path was structurally correct.

That pushed the investigation toward the instance bootstrap process.

---

## 3️⃣ Auto Scaling Was Actually Working

While troubleshooting, the Auto Scaling Group began replacing instances because the ELB health checks continued to fail.

AWS activity showed instances being terminated because of failed ELB health checks and replacement instances being launched.

This revealed an important distinction:

> **Auto Scaling itself wasn't broken. It was correctly reacting to unhealthy instances.**

But every replacement instance received the same Launch Template configuration.

That meant the same failure kept repeating:

```text
Launch instance
      ↓
Application unhealthy
      ↓
ELB health check fails
      ↓
ASG terminates instance
      ↓
ASG launches replacement
      ↓
Replacement receives same configuration
      ↓
Failure repeats
```

Replacing infrastructure does not fix a bad launch configuration.

---

## 4️⃣ Add Secure Diagnostic Access with Systems Manager

The EC2 instances were intentionally deployed in private subnets without SSH access.

Rather than opening port 22, I added AWS Systems Manager access through Terraform.

The relationship became:

```text
IAM Role
   ↓
AmazonSSMManagedInstanceCore
   ↓
IAM Instance Profile
   ↓
Launch Template
   ↓
EC2
   ↓
Systems Manager Session Manager
```

The Launch Template receives the instance profile through:

```hcl
iam_instance_profile {
  name = aws_iam_instance_profile.ec2_ssm.name
}
```

This allowed me to connect securely to the private instances without:

```text
Public IP       ❌
Inbound SSH     ❌
SSH key pair    ❌
```

Once connected through Session Manager, I checked Apache:

```bash
sudo systemctl status httpd --no-pager
```

The result was:

```text
Unit httpd.service could not be found.
```

That was an important clue.

Apache wasn't merely stopped.

**Apache had never been installed.**

---

## 5️⃣ Follow the Evidence into cloud-init

Next I inspected the cloud-init logs.

They showed:

```text
Failed to run module scripts-user
```

That moved the investigation directly to EC2 user data.

I inspected the actual script received by the instance:

```bash
sudo head -5 /var/lib/cloud/instance/scripts/part-001 | cat -A
```

The output revealed:

```text
 #!/bin/bash
 dnf update -y
 dnf install -y httpd
```

There was whitespace before the shebang.

The script needed to begin directly with:

```bash
#!/bin/bash
```

The malformed script explained the entire failure chain:

```text
User data fails
      ↓
Apache never installs
      ↓
Nothing listens on port 80
      ↓
ALB health check fails
      ↓
Instance becomes unhealthy
      ↓
ASG replaces instance
      ↓
Replacement receives same broken user data
      ↓
Cycle repeats
```

We had reached the root cause.

---

# 🛠️ Fixing the Root Cause

Instead of continuing to embed the script inside the Terraform heredoc, I moved the bootstrap logic into a standalone file:

```text
user_data.sh
```

The file begins correctly with:

```bash
#!/bin/bash
```

Terraform now reads it using:

```hcl
user_data = base64encode(file("${path.module}/user_data.sh"))
```

Updating the Launch Template created **Launch Template version 3**.

But creating a new Launch Template version alone does not automatically mean every existing EC2 instance is replaced.

I therefore initiated an **Auto Scaling Instance Refresh**.

The refresh gradually replaced the existing instances with instances launched from version 3 of the template.

![Launch Template v3 instance refresh](screenshots/03-launch-template-v3-instance-refresh-success.png)

After the refresh completed, the Auto Scaling Group showed two healthy `InService` instances running Launch Template version 3.

The Target Group then reported both instances:

```text
healthy
```

![Healthy ALB targets](screenshots/04-alb-targets-healthy-after-self-healing.png)

And the application finally loaded successfully through the ALB DNS name.

![Terraform ASG application](screenshots/01-terraform-asg-application-success.png)

## 🟢 Green Means GO!

---

# ♻️ Testing Auto Scaling Self-Healing

Getting the application healthy wasn't the end of the test.

I intentionally terminated one of the healthy EC2 instances to verify that the Auto Scaling Group could maintain desired capacity without manual intervention.

The expected behavior was:

```text
Desired Capacity = 2

One instance terminated
        ↓
Actual Capacity = 1
        ↓
ASG detects capacity mismatch
        ↓
Replacement EC2 launched
        ↓
Replacement enters InService
        ↓
ALB health checks pass
        ↓
Healthy Capacity = 2
```

During the test, the original instance transitioned to `Terminating` while the replacement instance entered `Pending`.

AWS scaling activity then confirmed that a replacement EC2 instance had been launched.

![Auto Scaling self-healing activity](screenshots/05-asg-self-healing-scaling-activities.png)

The replacement eventually registered as healthy in the Target Group:

![Healthy targets after self-healing](screenshots/04-alb-targets-healthy-after-self-healing.png)

The test demonstrated that the architecture wasn't simply running two EC2 instances.

The **Auto Scaling Group was actively maintaining the desired state of the application infrastructure.**

---

# 🔐 Terraform Remote State

The project initially used local Terraform state:

```text
Terraform
    ↓
terraform.tfstate
    ↓
AWS
```

For a more production-aligned configuration, I migrated the state to an Amazon S3 backend:

```text
Terraform
    ↓
S3 Remote Backend
    ↓
terraform-asg/terraform.tfstate
    ↓
AWS
```

The dedicated state bucket is:

```text
mandy-terraform-asg-state-2026
```

with the state stored at:

```text
terraform-asg/terraform.tfstate
```

---

## 🪣 Backend Configuration

The Terraform backend is configured in `providers.tf`:

```hcl
backend "s3" {
  bucket       = "mandy-terraform-asg-state-2026"
  key          = "terraform-asg/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
```

The existing local state was migrated using:

```bash
terraform init -migrate-state
```

The state object was then verified in S3.

![Terraform remote state in S3](screenshots/06-s3-remote-terraform-state.png)

---

# 🔒 Protecting Terraform State

Terraform state contains detailed information about managed infrastructure and can potentially contain sensitive values.

Before migrating the state, I configured several protections on the S3 bucket.

## Public Access Block

All four S3 public access settings were enabled:

```text
BlockPublicAcls       = true
IgnorePublicAcls      = true
BlockPublicPolicy     = true
RestrictPublicBuckets = true
```

![S3 public access blocked](screenshots/08-s3-public-access-blocked.png)

---

## Server-Side Encryption

The bucket uses S3 server-side encryption:

```text
AES256
```

![S3 state encryption](screenshots/09-s3-state-encryption-aes256.png)

---

## Versioning

S3 versioning is enabled.

This allows previous versions of the Terraform state object to be retained, providing additional recovery protection if the state object is accidentally overwritten or corrupted.

---

## State Locking

The S3 backend uses:

```hcl
use_lockfile = true
```

State locking helps prevent multiple Terraform operations from modifying the same state simultaneously.

This is especially important when Infrastructure as Code is managed collaboratively.

---

# ✅ Final Terraform Validation

After migrating the state to S3, I ran:

```bash
terraform plan
```

Terraform:

1. Read the remote state from S3
2. Refreshed the real AWS resources
3. Compared the infrastructure against the Terraform configuration
4. Found no drift

The result:

```text
No changes. Your infrastructure matches the configuration.
```

![Terraform plan no changes](screenshots/07-terraform-plan-no-changes.png)

That confirmed:

```text
Terraform configuration
        ↓
S3 remote state
        ↓
Real AWS infrastructure
        ↓
No differences
        ↓
🟢 GMG
```

---

# 📁 Repository Structure

```text
terraform-asg-deployment/
│
├── main.tf
├── providers.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── user_data.sh
├── .terraform.lock.hcl
├── .gitignore
├── README.md
│
└── screenshots/
    ├── 00-terraform-asg-architecture-diagram.png
    ├── 01-terraform-asg-application-success.png
    ├── 02-asg-healthy-multi-az-instances.png
    ├── 03-launch-template-v3-instance-refresh-success.png
    ├── 04-alb-targets-healthy-after-self-healing.png
    ├── 05-asg-self-healing-scaling-activities.png
    ├── 06-s3-remote-terraform-state.png
    ├── 07-terraform-plan-no-changes.png
    ├── 08-s3-public-access-blocked.png
    └── 09-s3-state-encryption-aes256.png
```

The following are intentionally excluded from version control:

```text
.terraform/
*.tfstate
*.tfstate.*
tfplan
*.tfplan
*.tfvars
*.tfvars.json
```

The `.terraform.lock.hcl` file **is committed** so the repository retains the Terraform provider dependency selections and checksums.

---

# 🧠 What I Learned

This project reinforced several concepts that go beyond simply getting Terraform to deploy successfully.

## 🔗 Terraform Resources Are Connected by Values

Terraform resources aren't isolated blocks of configuration.

Values flow between them:

```text
Resource
   ↓
Attribute
   ↓
Another Resource
```

For example:

```text
aws_vpc.main.id
        ↓
Subnets
Security Groups
Target Group
```

and:

```text
aws_lb_target_group.web.arn
        ↓
ALB Listener
Auto Scaling Group
```

Understanding these relationships made it much easier to reason about both the Terraform configuration and the resulting AWS architecture.

---

## 🩺 Infrastructure Health Is Not Application Health

An EC2 instance can be:

```text
Running
Healthy to EC2
InService in the ASG
```

while the application running on it is still broken.

The EC2 instances existed and Auto Scaling was functioning, but Apache had never been installed.

The ALB Target Group health checks exposed the application-layer failure.

---

## ♻️ Auto Scaling Is Only as Good as Its Launch Configuration

The Auto Scaling Group did exactly what it was designed to do.

It detected unhealthy instances and replaced them.

But:

```text
Broken Launch Template
        +
Automatic Replacement
        =
More identically broken instances
```

Self-healing infrastructure still depends on a healthy, repeatable launch configuration.

---

## 🔎 Troubleshoot the Whole Path

This project reinforced the troubleshooting method I want to continue using in cloud environments:

```text
Start with the symptom
        ↓
Follow the request path
        ↓
Verify each layer
        ↓
Collect evidence
        ↓
Eliminate healthy layers
        ↓
Find the failing layer
        ↓
Fix the root cause
        ↓
Validate end-to-end
```

Instead of randomly changing security groups, routes, or instances, each check narrowed the problem.

---

## 🔐 Secure Administration Doesn't Require SSH

AWS Systems Manager Session Manager allowed me to troubleshoot private EC2 instances without:

- Opening port 22
- Assigning public IP addresses
- Managing SSH keys

The IAM relationship was:

```text
EC2
 ↓
Instance Profile
 ↓
IAM Role
 ↓
AmazonSSMManagedInstanceCore
 ↓
Systems Manager
```

This provided a much more secure administrative path into the private instances.

---

## 🗃️ Terraform State Is Part of the Infrastructure

Remote state isn't just a Terraform configuration detail.

Terraform state is what maps:

```text
Terraform resource
        ↕
Actual AWS resource
```

Moving state to S3 introduced concepts that matter in real Infrastructure as Code workflows:

- Shared state
- Encryption
- Versioning
- Public access protection
- State locking
- State migration

---

# 🏁 Final Result

The completed project demonstrates:

```text
Infrastructure as Code          ✅
Custom VPC                      ✅
Multi-AZ architecture           ✅
Public/private subnet design    ✅
Private EC2 instances           ✅
Application Load Balancing      ✅
Auto Scaling                    ✅
ALB health checks               ✅
Self-healing                    ✅
Launch Template versioning      ✅
Instance refresh                ✅
Secure SSM administration       ✅
No SSH exposure                 ✅
Remote Terraform state          ✅
State encryption                ✅
State versioning                ✅
State locking                   ✅
Intentional failure testing     ✅
Root-cause troubleshooting      ✅
End-to-end validation           ✅
```

What began as a Terraform Auto Scaling deployment became a much better exercise in understanding how **networking, load balancing, Auto Scaling, EC2 bootstrap configuration, IAM, Systems Manager, Terraform resource linkage, and remote state all work together**.

Most importantly, the project reinforced that a successful Terraform deployment doesn't automatically mean the application is healthy.

Sometimes you have to follow the evidence all the way down to one tiny space before:

# 🟢 Green Means GO!