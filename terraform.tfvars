aws_region    = "ap-southeast-1"
project_name  = ""

# ต้อง unique ทั้งโลก
s3_bucket_name = ""
s3_prefix      = "outputs/"

alert_email = ""

# Notebook
notebook_name            = ""
notebook_instance_type   = "ml.t3.medium"
notebook_volume_size_gb  = 20

# Alarms
cpu_alarm_threshold  = 20
mem_alarm_threshold  = 40
disk_alarm_threshold = 40
alarm_evaluation_periods = 1

# Optional IAM User
create_iam_user                    = true
iam_user_name                      = "sm-console-user"
iam_user_console_password_length   = 20
create_access_key                  = false
