mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

run "github_instance_test" {
  command = plan

  variables {
    vpc_id                  = "vpc-1234567890abcdef0"
    vpc_cidr                = "10.0.0.0/16"
    key_name                = "ghes-key"
    allowed_cidr_ingress    = "10.0.0.0/16"
    private_subnet_ids      = ["subnet-11111111", "subnet-22222222"]
    availability_zones      = ["eu-west-2a", "eu-west-2b"]
    ami_id                  = "ami-0123456789abcdef0"
    github_backup_image     = "quay.io/example/ghes-backup:latest"
    aws_region              = "eu-west-2"
    ecr_account_id          = "123456789012"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
    ssh_private_key         = "test-private-key"
    cloudwatch_config       = "AmazonCloudWatch-ghes-config"
    environment             = "test"
    sns_email               = "alerts@example.com"
    ssm_logging_policy_name = "ssm-logging-policy"
    use_private_subnets     = true
    slack_webhook_url       = "https://example.com/slack-webhook"
  }

  assert {
    condition     = length(aws_instance.github_instance) == 2
    error_message = "Expected 2 GHES instances."
  }

  assert {
    condition     = length(aws_lb.nlb) == 2
    error_message = "Expected 2 network load balancers"
  }

  assert {
    condition     = length(aws_lb_listener.nlb_listener) == 14
    error_message = "Expected 14 NLB listeners (2 NLBs x 7 default ports)."
  }

  assert {
    condition     = length(aws_lb_target_group.tg) == 14
    error_message = "Expected 14 target groups (2 NLBs x 7 default ports)."
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.tg_attachment) == 14
    error_message = "Expected 14 target group attachments (2 instances x 7 default ports)."
  }

  assert {
    condition     = alltrue([for _, lb in aws_lb.nlb : lb.internal])
    error_message = "Expected all NLBs to be internal when use_private_subnets is true."
  }

  assert {
    condition     = alltrue([for _, instance in aws_instance.github_instance : instance.associate_public_ip_address == false])
    error_message = "Expected GHES instances to be private by default."
  }

  assert {
    condition     = output.vpc_id == "vpc-1234567890abcdef0"
    error_message = "Output vpc_id did not match the provided input."
  }
}

run "public_subnet_and_eip_test" {
  command = plan

  variables {
    vpc_id                  = "vpc-1234567890abcdef0"
    vpc_cidr                = "10.0.0.0/16"
    key_name                = "ghes-key"
    allowed_cidr_ingress    = "10.0.0.0/16"
    private_subnet_ids      = ["subnet-11111111", "subnet-22222222"]
    public_subnet_ids       = ["subnet-33333333", "subnet-44444444"]
    availability_zones      = ["eu-west-2a", "eu-west-2b"]
    ami_id                  = "ami-0123456789abcdef0"
    github_backup_image     = "quay.io/example/ghes-backup:latest"
    aws_region              = "eu-west-2"
    ecr_account_id          = "123456789012"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
    ssh_private_key         = "test-private-key"
    cloudwatch_config       = "AmazonCloudWatch-ghes-config"
    environment             = "test"
    sns_email               = "alerts@example.com"
    ssm_logging_policy_name = "ssm-logging-policy"
    use_private_subnets     = false
    public_ip               = true
    public_eip              = true
    slack_webhook_url       = "https://example.com/slack-webhook"
  }

  assert {
    condition     = alltrue([for _, lb in aws_lb.nlb : lb.internal == false])
    error_message = "Expected NLBs to be internet-facing when use_private_subnets is false."
  }

  assert {
    condition     = alltrue([for _, lb in aws_lb.nlb : length(lb.subnets) == 2 && contains(lb.subnets, "subnet-33333333") && contains(lb.subnets, "subnet-44444444")])
    error_message = "Expected NLBs to be placed in provided public subnets."
  }

  assert {
    condition     = alltrue([for _, instance in aws_instance.github_instance : instance.associate_public_ip_address == true])
    error_message = "Expected GHES instances to have public IP addresses when enabled."
  }

  assert {
    condition     = length(aws_eip.github_eip) == 2
    error_message = "Expected one EIP per GHES instance when public_eip is true."
  }
}

run "instance_role_enabled_test" {
  command = plan

  variables {
    vpc_id                  = "vpc-1234567890abcdef0"
    vpc_cidr                = "10.0.0.0/16"
    key_name                = "ghes-key"
    allowed_cidr_ingress    = "10.0.0.0/16"
    private_subnet_ids      = ["subnet-11111111", "subnet-22222222"]
    availability_zones      = ["eu-west-2a", "eu-west-2b"]
    ami_id                  = "ami-0123456789abcdef0"
    github_backup_image     = "quay.io/example/ghes-backup:latest"
    aws_region              = "eu-west-2"
    ecr_account_id          = "123456789012"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
    ssh_private_key         = "test-private-key"
    cloudwatch_config       = "AmazonCloudWatch-ghes-config"
    environment             = "test"
    sns_email               = "alerts@example.com"
    ssm_logging_policy_name = "ssm-logging-policy"
    use_private_subnets     = true
    enable_instance_role    = true
    slack_webhook_url       = "https://example.com/slack-webhook"
  }

  assert {
    condition     = length(aws_iam_role.instance_management_role) == 1
    error_message = "Expected module to create instance management role when enable_instance_role is true."
  }

  assert {
    condition     = length(data.aws_iam_role.instance_management_role) == 0
    error_message = "Expected no lookup of pre-existing role when enable_instance_role is true."
  }

  assert {
    condition     = length(aws_iam_policy.ssm_parameter_access) == 1 && length(aws_iam_policy.backup_host_s3_access) == 1
    error_message = "Expected module-managed IAM policies for SSM parameter and backup S3 access."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm_logging_policy_attachment) == 1 && length(aws_iam_role_policy_attachment.ssm_core) == 1 && length(aws_iam_role_policy_attachment.cloudwatch_agent) == 1 && length(aws_iam_role_policy_attachment.cloudwatch_logs) == 1 && length(aws_iam_role_policy_attachment.route_53_policy) == 1 && length(aws_iam_role_policy_attachment.ssm_parameter_policy_attachment) == 1 && length(aws_iam_role_policy_attachment.backup_host_s3_access_attachment) == 1
    error_message = "Expected all required IAM policy attachments when enable_instance_role is true."
  }
}