############################################
# main.tf (FULL)
# - Creates S3 bucket
# - Creates SageMaker execution role (service account)
# - Scopes S3 access to bucket + prefix
# - Creates SNS email alerts
# - Creates SageMaker notebook + lifecycle config (CloudWatch Agent)
# - Creates CloudWatch alarms (CPU + CWAgent mem/disk placeholders)
# - Optional IAM user for console login (+ change password + DataZone ListDomains)
############################################

data "aws_caller_identity" "current" {}

locals {
  name_prefix = var.project_name

  # Normalize prefix (no leading/trailing slash; allow empty)
  s3_prefix_clean = trim(var.s3_prefix, "/")
  s3_prefix_path  = local.s3_prefix_clean == "" ? "" : "${local.s3_prefix_clean}/"

  cw_agent_namespace = "CWAgent"
}

# ---------------------------
# S3 Bucket (CREATE REAL BUCKET)
# ---------------------------
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

# ---------------------------
# SNS topic + email subscription
# ---------------------------
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------
# IAM Role (SageMaker execution role = "service account")
# ---------------------------
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

# ---------------------------
# IAM Policy: S3 scoped access (bucket + prefix)
# ✅ FIX: allow ListBucket (so aws s3 ls works)
# ✅ Object RW limited to <bucket>/<prefix>/*
# ---------------------------
data "aws_iam_policy_document" "s3_scoped_access" {
  statement {
    sid     = "ListBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.sm_bucket.arn
    ]
  }

  statement {
    sid    = "ObjectScopedRW"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts"
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

# ---------------------------
# IAM Policy: CloudWatch logs + custom metric publish
# ---------------------------
data "aws_iam_policy_document" "cw_logs_access" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cw_logs_access" {
  name   = "${local.name_prefix}-cw-logs"
  policy = data.aws_iam_policy_document.cw_logs_access.json
}

resource "aws_iam_role_policy_attachment" "attach_s3_scoped" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.s3_scoped_access.arn
}

resource "aws_iam_role_policy_attachment" "attach_cw_logs" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.cw_logs_access.arn
}

# OPTIONAL (easy): give broad SageMaker permissions to execution role
resource "aws_iam_role_policy_attachment" "attach_managed_sagemaker" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# ---------------------------
# SageMaker Notebook Lifecycle Config: install + start CloudWatch Agent
# (publishes RAM/Disk metrics)
#
# NOTE: This resource failed earlier in some regions.
# ap-southeast-1 should support it, but if it fails, comment it + lifecycle_config_name below.
# ---------------------------
resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "cwagent" {
  name = "${local.name_prefix}-nb-lc"

  on_start = base64encode(<<-EOT
    #!/bin/bash
    set -e

    echo "=== Installing CloudWatch Agent ==="
    sudo yum install -y amazon-cloudwatch-agent || true

    echo "=== Writing CloudWatch Agent config ==="
    sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json >/dev/null <<'JSON'
    {
      "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
      },
      "metrics": {
        "namespace": "${local.cw_agent_namespace}",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}"
        },
        "metrics_collected": {
          "cpu": {
            "measurement": [
              { "name": "cpu_usage_idle", "rename": "cpu_usage_idle", "unit": "Percent" },
              { "name": "cpu_usage_user", "rename": "cpu_usage_user", "unit": "Percent" },
              { "name": "cpu_usage_system", "rename": "cpu_usage_system", "unit": "Percent" }
            ],
            "metrics_collection_interval": 60,
            "totalcpu": true
          },
          "mem": {
            "measurement": [
              { "name": "mem_used_percent", "rename": "mem_used_percent", "unit": "Percent" }
            ],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": [
              { "name": "disk_used_percent", "rename": "disk_used_percent", "unit": "Percent" }
            ],
            "metrics_collection_interval": 60,
            "resources": ["/"]
          }
        }
      }
    }
JSON

    echo "=== Starting CloudWatch Agent ==="
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop || true

    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
      -s

    echo "=== CloudWatch Agent started ==="
  EOT
  )
}

# ---------------------------
# SageMaker Notebook Instance
# ---------------------------
resource "aws_sagemaker_notebook_instance" "notebook" {
  name                  = var.notebook_name != "" ? var.notebook_name : "${local.name_prefix}-notebook"
  role_arn               = aws_iam_role.sagemaker_execution.arn
  instance_type          = var.notebook_instance_type
  volume_size            = var.notebook_volume_size_gb
  lifecycle_config_name  = aws_sagemaker_notebook_instance_lifecycle_configuration.cwagent.name
  direct_internet_access = "Enabled"
  root_access            = "Enabled"

  tags = {
    Project = var.project_name
  }
}

# ---------------------------
# CloudWatch alarms -> SNS
# ---------------------------

# CPU (SageMaker built-in)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  alarm_description   = "SageMaker Notebook CPUUtilization is high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  threshold           = var.cpu_alarm_threshold
  statistic           = "Average"
  treat_missing_data  = "missing"

  namespace   = "AWS/SageMaker"
  metric_name = "CPUUtilization"

  dimensions = {
    NotebookInstanceName = aws_sagemaker_notebook_instance.notebook.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# NOTE:
# RAM/Disk are CWAgent custom metrics and require correct dimensions.
# We set placeholder dimensions and ignore changes, then you update once you confirm dimensions in CloudWatch.
resource "aws_cloudwatch_metric_alarm" "mem_high" {
  alarm_name          = "${local.name_prefix}-mem-high"
  alarm_description   = "Notebook mem_used_percent is high (CloudWatch Agent)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  threshold           = var.mem_alarm_threshold
  statistic           = "Average"
  treat_missing_data  = "missing"

  namespace   = local.cw_agent_namespace
  metric_name = "mem_used_percent"

  dimensions = {
    InstanceId = "UNKNOWN_AT_PLAN_TIME"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  lifecycle {
    ignore_changes = [dimensions]
  }
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name          = "${local.name_prefix}-disk-high"
  alarm_description   = "Notebook disk_used_percent is high (CloudWatch Agent)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  threshold           = var.disk_alarm_threshold
  statistic           = "Average"
  treat_missing_data  = "missing"

  namespace   = local.cw_agent_namespace
  metric_name = "disk_used_percent"

  dimensions = {
    InstanceId = "UNKNOWN_AT_PLAN_TIME"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  lifecycle {
    ignore_changes = [dimensions]
  }
}

# ---------------------------
# IAM USER (human) for AWS Console login (SageMaker UI)
# ---------------------------
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

# allow IAM user to change their own password (first login reset)
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

# SageMaker console calls DataZone (ListDomains) - add permission for console user
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

# Console login profile (Terraform outputs a temporary password)
resource "aws_iam_user_login_profile" "human_console" {
  count                   = var.create_iam_user ? 1 : 0
  user                    = aws_iam_user.human[0].name
  password_length         = var.iam_user_console_password_length
  password_reset_required = true
}

# Optional: programmatic access key (CLI) - only if you need it
resource "aws_iam_access_key" "human_key" {
  count = (var.create_iam_user && var.create_access_key) ? 1 : 0
  user  = aws_iam_user.human[0].name
}
