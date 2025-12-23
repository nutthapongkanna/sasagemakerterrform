############################################
# outputs.tf
############################################

output "aws_account_id" {
  description = "AWS Account ID"
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
  description = "SageMaker execution role ARN"
  value       = aws_iam_role.sagemaker_execution.arn
}

output "sagemaker_notebook_name" {
  description = "SageMaker notebook instance name"
  value       = aws_sagemaker_notebook_instance.notebook.name
}

output "cloudwatch_namespace" {
  description = "CloudWatch Agent namespace"
  value       = local.cw_agent_namespace
}

# IAM user outputs (only when created)
output "iam_user_name" {
  description = "IAM user for console login (if created)"
  value       = var.create_iam_user ? aws_iam_user.human[0].name : null
}

output "iam_user_console_password" {
  description = "Temporary console password (if created)"
  value       = var.create_iam_user ? aws_iam_user_login_profile.human_console[0].password : null
  sensitive   = true
}

output "iam_user_access_key_id" {
  description = "Access key id (if created)"
  value       = (var.create_iam_user && var.create_access_key) ? aws_iam_access_key.human_key[0].id : null
  sensitive   = true
}

output "iam_user_secret_access_key" {
  description = "Secret access key (if created)"
  value       = (var.create_iam_user && var.create_access_key) ? aws_iam_access_key.human_key[0].secret : null
  sensitive   = true
}
