#!/bin/bash
dnf update -y
dnf install -y httpd
systemctl enable httpd
systemctl start httpd

cat <<'HTML' > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
  <title>Mandy's Terraform ASG</title>
  <style>
    body {
      background: #0f172a;
      color: #e2e8f0;
      font-family: Arial, sans-serif;
      text-align: center;
      padding-top: 100px;
    }

    .card {
      background: #1e293b;
      max-width: 650px;
      margin: auto;
      padding: 40px;
      border-radius: 16px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.35);
    }

    h1 {
      color: #4ade80;
    }

    .status {
      color: #4ade80;
      font-weight: bold;
    }

    .path {
      background: #0f172a;
      padding: 15px;
      border-radius: 8px;
      margin-top: 25px;
      font-family: monospace;
    }
  </style>
</head>

<body>
  <div class="card">
    <h1>☁️ Terraform ASG Deployment</h1>
    <h2>Green Means GO! 🟢</h2>

    <p class="status">Apache is running successfully.</p>

    <p>
      This server was launched automatically by an
      AWS Auto Scaling Group built with Terraform.
    </p>

    <div class="path">
      Internet → ALB → Target Group → ASG → EC2
    </div>

    <p>Infrastructure as Code + High Availability 🚀</p>
  </div>
</body>
</html>
HTML