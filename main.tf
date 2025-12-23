############################################
# main.tf (FULL - FINAL, ALL INCLUDED)
############################################


data "aws_caller_identity" "current" {}

############################
# LOCALS
############################
locals {
  name_prefix = var.project_name

  s3_prefix_clean = trim(var.s3_prefix, "/")
  s3_prefix_path  = local.s3_prefix_clean == "" ? "" : "${local.s3_prefix_clean}/"

  cw_agent_namespace = "CWAgent"

  # ป้องกัน terraform cycle
  notebook_effective_name = (
    var.notebook_name != ""
    ? var.notebook_name
    : "${var.project_name}-notebook"
  )
}

############################
# S3 BUCKET
############################
resource "aws_s3_bucket" "sm_bucket" {
  bucket = var.s3_bucket_name
  tags = {
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "sm_bucket" {
  bucket                  = aws_s3_bucket.sm_bucket.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

############################
# SNS (EMAIL ALERT)
############################
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

############################
# IAM ROLE (SAGEMAKER EXECUTION)
############################
data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "sagemaker_execution" {
  name               = "${local.name_prefix}-sagemaker-exec"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

############################
# IAM POLICIES
############################
data "aws_iam_policy_document" "s3_scoped_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.sm_bucket.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.sm_bucket.arn}/${local.s3_prefix_path}*"
    ]
  }
}

resource "aws_iam_policy" "s3_scoped_access" {
  name   = "${local.name_prefix}-s3-scoped"
  policy = data.aws_iam_policy_document.s3_scoped_access.json
}

data "aws_iam_policy_document" "cw_logs_access" {
  statement {
    effect = "Allow"
    actions = [
      "logs:*",
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cw_logs_access" {
  name   = "${local.name_prefix}-cw-logs"
  policy = data.aws_iam_policy_document.cw_logs_access.json
}

resource "aws_iam_role_policy_attachment" "attach_s3" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.s3_scoped_access.arn
}

resource "aws_iam_role_policy_attachment" "attach_cw" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.cw_logs_access.arn
}

resource "aws_iam_role_policy_attachment" "attach_sagemaker" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

############################
# NOTEBOOK LIFECYCLE (CWAGENT)
############################
resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "cwagent" {
  name = "${local.name_prefix}-nb-lc"

  on_start = base64encode(<<-EOT
#!/bin/bash
set +e

yum install -y amazon-cloudwatch-agent || true

cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'JSON'
{
  "agent": {
    "metrics_collection_interval": 60
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "NotebookInstanceName": "${local.notebook_effective_name}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/", "/home/ec2-user/SageMaker"]
      }
    }
  }
}
JSON

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s || true

exit 0
EOT
  )
}

############################
# SAGEMAKER NOTEBOOK
############################
resource "aws_sagemaker_notebook_instance" "notebook" {
  name                  = local.notebook_effective_name
  role_arn              = aws_iam_role.sagemaker_execution.arn
  instance_type         = var.notebook_instance_type
  volume_size           = var.notebook_volume_size_gb
  lifecycle_config_name = aws_sagemaker_notebook_instance_lifecycle_configuration.cwagent.name

  direct_internet_access = "Enabled"
  root_access            = "Enabled"

  tags = {
    Project = var.project_name
  }
}

############################
# CLOUDWATCH ALARMS
############################

# CPU
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.cpu_alarm_threshold
  evaluation_periods  = 1
  period              = 60
  statistic           = "Average"

  namespace   = "AWS/SageMaker"
  metric_name = "CPUUtilization"

  dimensions = {
    NotebookInstanceName = local.notebook_effective_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# MEMORY (CWAGENT)
resource "aws_cloudwatch_metric_alarm" "mem_high" {
  alarm_name          = "${local.name_prefix}-mem-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.mem_alarm_threshold
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      namespace   = "CWAgent"
      metric_name = "mem_used_percent"
      stat        = "Maximum"
      period      = 60
      dimensions = {
        NotebookInstanceName = local.notebook_effective_name
      }
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# DISK (WORKSPACE)
resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name          = "${local.name_prefix}-disk-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.disk_alarm_threshold
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      namespace   = "CWAgent"
      metric_name = "disk_used_percent"
      stat        = "Maximum"
      period      = 60
      dimensions = {
        path = "/home/ec2-user/SageMaker"
      }
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

############################
# IAM USER (HUMAN - CONSOLE LOGIN)
############################
resource "aws_iam_user" "human" {
  count = var.create_iam_user ? 1 : 0
  name  = var.iam_user_name

  tags = {
    Project = var.project_name
    Type    = "HumanLogin"
  }
}

resource "aws_iam_user_policy_attachment" "human_sagemaker_full" {
  count      = var.create_iam_user ? 1 : 0
  user       = aws_iam_user.human[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_user_policy_attachment" "human_iam_readonly" {
  count      = var.create_iam_user ? 1 : 0
  user       = aws_iam_user.human[0].name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

data "aws_iam_policy_document" "human_allow_change_password" {
  statement {
    effect = "Allow"
    actions = [
      "iam:GetAccountPasswordPolicy",
      "iam:ChangePassword"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "human_allow_change_password" {
  count  = var.create_iam_user ? 1 : 0
  name   = "${local.name_prefix}-allow-self-change-password"
  user   = aws_iam_user.human[0].name
  policy = data.aws_iam_policy_document.human_allow_change_password.json
}

data "aws_iam_policy_document" "human_allow_datazone_listdomains" {
  statement {
    effect  = "Allow"
    actions = ["datazone:ListDomains"]
    resources = [
      "arn:aws:datazone:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/*"
    ]
  }
}

resource "aws_iam_user_policy" "human_allow_datazone_listdomains" {
  count  = var.create_iam_user ? 1 : 0
  name   = "${local.name_prefix}-allow-datazone-listdomains"
  user   = aws_iam_user.human[0].name
  policy = data.aws_iam_policy_document.human_allow_datazone_listdomains.json
}

resource "aws_iam_user_login_profile" "human_console" {
  count                   = var.create_iam_user ? 1 : 0
  user                    = aws_iam_user.human[0].name
  password_length         = var.iam_user_console_password_length
  password_reset_required = true
}

resource "aws_iam_access_key" "human_key" {
  count = (var.create_iam_user && var.create_access_key) ? 1 : 0
  user  = aws_iam_user.human[0].name
}
