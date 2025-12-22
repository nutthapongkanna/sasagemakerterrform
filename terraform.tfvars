aws_region   = "ap-southeast-1"
project_name = "sm-lab"

alert_email = "you@example.com"

s3_bucket_name = "my-sagemaker-bucket"
s3_prefix      = "sagemaker/"

notebook_instance_type  = "ml.t3.medium"
notebook_volume_size_gb = 20

cpu_alarm_threshold  = 80
mem_alarm_threshold  = 80
disk_alarm_threshold = 80

alarm_period_seconds     = 300
alarm_evaluation_periods = 1

create_iam_user = true
iam_user_name   = ""
create_access_key = false
