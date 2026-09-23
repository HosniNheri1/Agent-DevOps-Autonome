terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ============================================
# VPC & NETWORKING
# ============================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "agent-devops-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "agent-devops-igw"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "agent-devops-public-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "agent-devops-public-2"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "agent-devops-public-rt"
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "agent-devops-web-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "agent-devops-web-sg"
  }
}

# ============================================
# EC2 & AUTO SCALING
# ============================================

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_iam_role" "ssm_ec2" {
  name = "agent-devops-ssm-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "agent-devops-ssm-ec2-role"
  }
}

resource "aws_iam_role_policy" "ssm_ec2" {
  name = "agent-devops-ssm-ec2-policy"
  role = aws_iam_role.ssm_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ssm" {
  name = "agent-devops-ssm-profile"
  role = aws_iam_role.ssm_ec2.name
}

resource "aws_launch_template" "web" {
  name_prefix   = "agent-devops-web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ssm.name
  }

    user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    amazon-linux-extras install -y nginx1
    systemctl enable nginx
    systemctl start nginx
    echo "SSM Agent and nginx installed and started"
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "agent-devops-web"
    }
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "agent-devops-asg"
  vpc_zone_identifier = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  target_group_arns   = [aws_lb_target_group.web.arn]
  health_check_type   = "ELB"
  min_size            = 1
  max_size            = 3
  desired_capacity    = 2

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "agent-devops-asg"
    propagate_at_launch = true
  }
}

# ============================================
# LOAD BALANCER
# ============================================

resource "aws_lb" "web" {
  name               = "agent-devops-alb-v2"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "agent-devops-alb-2"
  }
}

resource "aws_lb_target_group" "web" {
  name     = "agent-devops-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ============================================
# RDS DATABASE
# ============================================

resource "aws_db_subnet_group" "main" {
  name       = "agent-devops-db-subnet"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "agent-devops-db-subnet"
  }
}

resource "aws_db_instance" "main" {
  identifier             = "agent-devops-db-2"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "agentdevops"
  username               = "admin"
  password               = "Takecare55!"
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.web.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  tags = {
    Name = "agent-devops-db"
  }
}

# ============================================
# CLOUDWATCH ALARMS & SNS
# ============================================

resource "aws_sns_topic" "alarms" {
  name = "agent-devops-alarms"

  tags = {
    Name = "agent-devops-alarms"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "agent-devops-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alarme quand CPU > 80% pendant 5 minutes"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  tags = {
    Name = "agent-devops-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "agent-devops-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alarme quand erreurs 5xx > 5 sur l'ALB"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
  }

  tags = {
    Name = "agent-devops-error-rate"
  }
}

# ============================================
# CLOUDTRAIL & AUDIT
# ============================================

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "agent-devops-cloudtrail"
  retention_in_days = 7

  tags = {
    Name = "agent-devops-cloudtrail"
  }
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "agent-devops-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "agent-devops-cloudtrail"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${aws_s3_bucket.cloudtrail.id}"
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${aws_s3_bucket.cloudtrail.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name           = "agent-devops-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Name = "agent-devops-trail"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

data "aws_caller_identity" "current" {}

# ============================================
# LAMBDA INGESTION (Diagnostic)
# ============================================

resource "aws_iam_role" "lambda_ingestion" {
  name = "agent-devops-lambda-ingestion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "agent-devops-lambda-ingestion-role"
  }
}

resource "aws_iam_role_policy" "lambda_ingestion" {
  name = "agent-devops-lambda-ingestion-policy"
  role = aws_iam_role.lambda_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.current.account_id}:function:agent-devops-remediation"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "ingestion" {
  filename         = "${path.module}/../lambda/ingestion/lambda_ingestion.zip"
  function_name    = "agent-devops-ingestion"
  role             = aws_iam_role.lambda_ingestion.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  tags = {
    Name = "agent-devops-ingestion"
  }
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarms.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ingestion.arn
}

# ============================================
# SSM DOCUMENTS
# ============================================

resource "aws_ssm_document" "restart_service" {
  name          = "agent-devops-restart-service"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Redemarrer le service nginx"
    parameters = {
      serviceName = {
        type        = "String"
        description = "Nom du service a redemarrer"
        default     = "nginx"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "restartService"
        inputs = {
          runCommand = [
            "sudo systemctl restart {{ serviceName }}",
            "sudo systemctl status {{ serviceName }}"
          ]
        }
      }
    ]
  })

  tags = {
    Name = "agent-devops-restart-service"
  }
}

resource "aws_ssm_document" "scale_up_asg" {
  name          = "agent-devops-scale-up"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Augmenter la capacite de l'Auto Scaling Group"
    parameters = {
      asgName = {
        type        = "String"
        description = "Nom de l'Auto Scaling Group"
        default     = "agent-devops-asg"
      }
      desiredCapacity = {
        type        = "String"
        description = "Capacite desiree"
        default     = "3"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "scaleUp"
        inputs = {
          runCommand = [
            "aws autoscaling update-auto-scaling-group --auto-scaling-group-name {{ asgName }} --desired-capacity {{ desiredCapacity }} --region us-east-1"
          ]
        }
      }
    ]
  })

  tags = {
    Name = "agent-devops-scale-up"
  }
}

resource "aws_ssm_document" "rollback_deployment" {
  name          = "agent-devops-rollback"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Restaurer la version precedente du deploiement"
    parameters = {
      appPath = {
        type        = "String"
        description = "Chemin de l'application"
        default     = "/var/www/app"
      }
      serviceName = {
        type        = "String"
        description = "Nom du service a redemarrer"
        default     = "nginx"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "rollbackDeployment"
        inputs = {
          runCommand = [
            "cd {{ appPath }}",
            "git log --oneline -3",
            "git reset --hard HEAD~1",
            "sudo systemctl restart {{ serviceName }}",
            "sudo systemctl status {{ serviceName }}"
          ]
        }
      }
    ]
  })

  tags = {
    Name = "agent-devops-rollback"
  }
}

# IAM Role pour SSM execution
resource "aws_iam_role" "ssm" {
  name = "agent-devops-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "agent-devops-ssm-role"
  }
}

resource "aws_iam_role_policy" "ssm" {
  name = "agent-devops-ssm-policy"
  role = aws_iam_role.ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Name" = "agent-devops-*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================
# DYNAMODB ANTI-FLAPPING
# ============================================

resource "aws_dynamodb_table" "remediation_locks" {
  name           = "agent-devops-remediation-locks"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "instance_id"

  attribute {
    name = "instance_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl_timestamp"
    enabled        = true
  }

  tags = {
    Name = "agent-devops-remediation-locks"
  }
}

# ============================================
# LAMBDA REMEDIATION (Anti-Flapping + SSM)
# ============================================

resource "aws_iam_role" "lambda_remediation" {
  name = "agent-devops-lambda-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "agent-devops-lambda-remediation-role"
  }
}

resource "aws_iam_role_policy" "lambda_remediation" {
  name = "agent-devops-lambda-remediation-policy"
  role = aws_iam_role.lambda_remediation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:us-east-1:*:log-group:/aws/lambda/agent-devops-remediation:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.remediation_locks.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "remediation" {
  function_name = "agent-devops-remediation"
  role          = aws_iam_role.lambda_remediation.arn
  handler       = "remediation_handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  filename         = "${path.module}/../agent/remediation/lambda_remediation.zip"
  source_code_hash = filebase64sha256("${path.module}/../agent/remediation/lambda_remediation.zip")

  environment {
    variables = {
      DYNAMODB_TABLE     = aws_dynamodb_table.remediation_locks.name
      COOLDOWN_SECONDS   = "600"
    }
  }

  tags = {
    Name = "agent-devops-remediation"
  }
}
