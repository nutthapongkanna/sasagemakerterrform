############################################
# outputs.tf
############################################

output "aws_account_id" {
  description = "AWS Account ID that Terraform is running against"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "s3_bucket_name" {
  description = "S3 bucket created/used for SageMaker data & outputs"
  value       = aws_s3_bucket.sm_bucket.bucket
}

output "s3_prefix" {
  description = "S3 prefix used for scoped access"
  value       = local.s3_prefix_path
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  value       = aws_sns_topic.alerts.arn
}

output "sagemaker_execution_role_arn" {
  description = "Execution role ARN for SageMaker (service account)"
  value       = aws_iam_role.sagemaker_execution.arn
}

output "notebook_name" {
  description = "SageMaker Notebook instance name"
  value       = aws_sagemaker_notebook_instance.notebook.name
}

output "notebook_arn" {
  description = "SageMaker Notebook instance ARN"
  value       = aws_sagemaker_notebook_instance.notebook.arn
}

output "notebook_url" {
  description = "Notebook URL (may be empty until InService)"
  value       = aws_sagemaker_notebook_instance.notebook.url
}

output "cloudwatch_namespace" {
  description = "Namespace used by CloudWatch Agent custom metrics"
  value       = local.cw_agent_namespace
}

output "alarm_cpu_name" {
  description = "CloudWatch alarm name for CPU high"
  value       = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
}

output "alarm_mem_name" {
  description = "CloudWatch alarm name for memory high"
  value       = aws_cloudwatch_metric_alarm.mem_high.alarm_name
}

output "alarm_disk_name" {
  description = "CloudWatch alarm name for disk high"
  value       = aws_cloudwatch_metric_alarm.disk_high.alarm_name
}

output "iam_user_name" {
  description = "IAM user created for AWS Console login (if enabled)"
  value       = var.create_iam_user ? aws_iam_user.human[0].name : null
}

output "iam_user_temp_password" {
  description = "Temporary console password (ONLY available at creation time). If you recreate the login profile, it will change."
  value       = var.create_iam_user ? aws_iam_user_login_profile.human_console[0].password : null
  sensitive   = true
}
