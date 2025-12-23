aws_region    = "ap-southeast-1"
project_name  = "sm-lab"

# ต้อง unique ทั้งโลก
s3_bucket_name = "sm-lab-nutthapong-1234567890"
s3_prefix      = "outputs/"

alert_email = "you@example.com"

# Notebook
notebook_name            = "sm-lab-notebook"
notebook_instance_type   = "ml.t3.medium"
notebook_volume_size_gb  = 20

# Alarms
alarm_evaluation_periods = 1
cpu_alarm_threshold      = 80
mem_alarm_threshold      = 80
disk_alarm_threshold     = 80

# Optional IAM User
create_iam_user                    = true
iam_user_name                      = "sm-console-user"
iam_user_console_password_length   = 20
create_access_key                  = false
