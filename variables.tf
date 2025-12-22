variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "project_name" {
  type        = string
  description = "Prefix for resource names"
}

variable "alert_email" {
  type        = string
  description = "Email to receive CloudWatch alarm notifications (SNS subscription confirmation required)"
}

variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket name used by SageMaker"
}

variable "s3_prefix" {
  type        = string
  description = "S3 prefix (folder) allowed for access (e.g. 'sagemaker/' or '')"
  default     = ""
}

variable "notebook_instance_type" {
  type        = string
  description = "SageMaker notebook instance type"
  default     = "ml.t3.medium"
}

variable "notebook_volume_size_gb" {
  type        = number
  description = "Notebook EBS volume size (GB)"
  default     = 20
}

variable "cpu_alarm_threshold" {
  type        = number
  description = "CPUUtilization threshold (%)"
  default     = 80
}

variable "mem_alarm_threshold" {
  type        = number
  description = "mem_used_percent threshold (%) (custom metric from CloudWatch Agent)"
  default     = 80
}

variable "disk_alarm_threshold" {
  type        = number
  description = "disk_used_percent threshold (%) (custom metric from CloudWatch Agent)"
  default     = 80
}

variable "alarm_period_seconds" {
  type        = number
  description = "CloudWatch alarm period in seconds"
  default     = 300
}

variable "alarm_evaluation_periods" {
  type        = number
  description = "How many periods to evaluate before alarming"
  default     = 1
}

# -----------------------------
# IAM User (human) for console
# -----------------------------
variable "create_iam_user" {
  type        = bool
  description = "Create a human IAM user for AWS Console login"
  default     = true
}

variable "iam_user_name" {
  type        = string
  description = "IAM username for console login"
  default     = "sagemaker-user"
}

variable "iam_user_console_password_length" {
  type        = number
  description = "Temporary console password length"
  default     = 20
}

variable "create_access_key" {
  type        = bool
  description = "Also create programmatic access key (optional)"
  default     = false
}
