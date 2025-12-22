output "account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS Account ID (use for console sign-in URL if needed)"
}

output "sagemaker_execution_role_arn" {
  value       = aws_iam_role.sagemaker_execution.arn
  description = "IAM Role used by SageMaker (service account equivalent)"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "SNS topic for alerts"
}

output "notebook_name" {
  value       = aws_sagemaker_notebook_instance.notebook.name
  description = "SageMaker notebook instance name"
}

output "iam_username" {
  value       = var.create_iam_user ? aws_iam_user.human[0].name : null
  description = "IAM username for console login"
}

output "iam_user_console_password" {
  value       = var.create_iam_user ? aws_iam_user_login_profile.human_console[0].password : null
  description = "Temporary console password (change required at first login)"
  sensitive   = true
}

output "iam_user_access_key_id" {
  value       = (var.create_iam_user && var.create_access_key) ? aws_iam_access_key.human_key[0].id : null
  description = "Access key id (if create_access_key=true)"
}

output "iam_user_secret_access_key" {
  value       = (var.create_iam_user && var.create_access_key) ? aws_iam_access_key.human_key[0].secret : null
  description = "Secret access key (if create_access_key=true)"
  sensitive   = true
}
