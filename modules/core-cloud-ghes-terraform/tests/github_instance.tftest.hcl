mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z1234567890ABC"
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
    ami_id                  = "ami-0123456789abcdef0"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
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
    condition     = length(aws_lb_listener.nlb_listener) == (2 * length(var.port_to_name_map))
    error_message = "Expected listeners to equal 2 NLBs multiplied by configured ports."
  }

  assert {
    condition     = length(aws_lb_target_group.tg) == (2 * length(var.port_to_name_map))
    error_message = "Expected target groups to equal 2 NLBs multiplied by configured ports."
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.tg_attachment) == (2 * length(var.port_to_name_map))
    error_message = "Expected target group attachments to equal 2 instances multiplied by configured ports."
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

  assert {
    condition     = output.route53_zone_id == "Zone not managed by Terraform"
    error_message = "Expected Route53 output to report unmanaged zone when zone variables are empty."
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
    ami_id                  = "ami-0123456789abcdef0"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
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
    ami_id                  = "ami-0123456789abcdef0"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
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

run "instance_role_disabled_test" {
  command = plan

  variables {
    vpc_id                  = "vpc-1234567890abcdef0"
    vpc_cidr                = "10.0.0.0/16"
    key_name                = "ghes-key"
    allowed_cidr_ingress    = "10.0.0.0/16"
    private_subnet_ids      = ["subnet-11111111", "subnet-22222222"]
    ami_id                  = "ami-0123456789abcdef0"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
    cloudwatch_config       = "AmazonCloudWatch-ghes-config"
    environment             = "test"
    sns_email               = "alerts@example.com"
    ssm_logging_policy_name = "ssm-logging-policy"
    use_private_subnets     = true
    enable_instance_role    = false
    slack_webhook_url       = "https://example.com/slack-webhook"
  }

  assert {
    condition     = length(data.aws_iam_role.instance_management_role) == 1
    error_message = "Expected a pre-existing IAM role lookup when enable_instance_role is false."
  }

  assert {
    condition     = length(aws_iam_role.instance_management_role) == 0
    error_message = "Expected no module-managed IAM role when enable_instance_role is false."
  }

  assert {
    condition     = length(aws_iam_policy.ssm_parameter_access) == 0 && length(aws_iam_policy.backup_host_s3_access) == 0
    error_message = "Expected no module-managed IAM policies when enable_instance_role is false."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm_logging_policy_attachment) == 0 && length(aws_iam_role_policy_attachment.ssm_core) == 0 && length(aws_iam_role_policy_attachment.cloudwatch_agent) == 0 && length(aws_iam_role_policy_attachment.cloudwatch_logs) == 0 && length(aws_iam_role_policy_attachment.route_53_policy) == 0 && length(aws_iam_role_policy_attachment.ssm_parameter_policy_attachment) == 0 && length(aws_iam_role_policy_attachment.backup_host_s3_access_attachment) == 0
    error_message = "Expected no module-managed IAM policy attachments when enable_instance_role is false."
  }
}

run "monitoring_resources_test" {
  command = plan

  variables {
    vpc_id                  = "vpc-1234567890abcdef0"
    vpc_cidr                = "10.0.0.0/16"
    key_name                = "ghes-key"
    allowed_cidr_ingress    = "10.0.0.0/16"
    private_subnet_ids      = ["subnet-11111111", "subnet-22222222"]
    ami_id                  = "ami-0123456789abcdef0"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
    cloudwatch_config       = "AmazonCloudWatch-ghes-config"
    environment             = "test"
    sns_email               = "alerts@example.com"
    ssm_logging_policy_name = "ssm-logging-policy"
    use_private_subnets     = true
    slack_webhook_url       = "https://example.com/slack-webhook"
  }

  assert {
    condition     = aws_sns_topic.cloudwatch_alarm_topic.name == "github-test-cloudwatch-alarms" && aws_sns_topic_subscription.alarm_subscription.protocol == "email" && aws_sns_topic_subscription.alarm_subscription.endpoint == "alerts@example.com"
    error_message = "Expected SNS topic and email subscription for alarm notifications."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_usage_alarm) == 2 && length(aws_cloudwatch_metric_alarm.memory_usage_alarm) == 2 && length(aws_cloudwatch_metric_alarm.disk_usage_alarm) == 2
    error_message = "Expected one CPU, memory, and disk alarm per GHES instance."
  }
}

run "route53_records_enabled_test" {
  command = plan

  variables {
    vpc_id                  = "vpc-1234567890abcdef0"
    vpc_cidr                = "10.0.0.0/16"
    key_name                = "ghes-key"
    allowed_cidr_ingress    = "10.0.0.0/16"
    private_subnet_ids      = ["subnet-11111111", "subnet-22222222"]
    ami_id                  = "ami-0123456789abcdef0"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
    cloudwatch_config       = "AmazonCloudWatch-ghes-config"
    environment             = "test"
    sns_email               = "alerts@example.com"
    ssm_logging_policy_name = "ssm-logging-policy"
    use_private_subnets     = true
    route53_zone_name       = "example.com"
    route53_record_name     = "ghes"
    slack_webhook_url       = "https://example.com/slack-webhook"
  }

  assert {
    condition     = length(data.aws_route53_zone.selected) == 1
    error_message = "Expected Route53 zone lookup when zone name is provided."
  }

  assert {
    condition     = length(aws_route53_record.github_a_record) == 2 && length(aws_route53_record.github_wildcard_record) == 2
    error_message = "Expected weighted A and wildcard records for both GHES load balancers."
  }

  assert {
    condition     = output.route53_zone_id != "Zone not managed by Terraform"
    error_message = "Expected Route53 output to report managed zone when zone variables are provided."
  }
}

run "ses_config_enabled_test" {
  command = plan

  variables {
    vpc_id                  = "vpc-1234567890abcdef0"
    vpc_cidr                = "10.0.0.0/16"
    key_name                = "ghes-key"
    allowed_cidr_ingress    = "10.0.0.0/16"
    private_subnet_ids      = ["subnet-11111111", "subnet-22222222"]
    ami_id                  = "ami-0123456789abcdef0"
    ghe_hostname            = "ghes.example.internal"
    s3_bucket               = "example-ghes-backups"
    root_volume_size        = 100
    ebs_volume_size         = 500
    backup_root_volume_size = 150
    cloudwatch_config       = "AmazonCloudWatch-ghes-config"
    environment             = "test"
    sns_email               = "alerts@example.com"
    ssm_logging_policy_name = "ssm-logging-policy"
    use_private_subnets     = true
    route53_zone_name       = "example.com"
    create_ses_config       = true
    ses_domain_name         = "example.com"
    slack_webhook_url       = "https://example.com/slack-webhook"
  }

  assert {
    condition     = length(aws_ses_domain_identity.ses_domain) == 1 && length(aws_ses_domain_dkim.dkim) == 1 && length(aws_ses_domain_mail_from.mail_from) == 1
    error_message = "Expected SES identity, DKIM, and MAIL FROM resources when SES config is enabled."
  }

  assert {
    condition     = length(aws_route53_record.ses_verification) == 1 && length(aws_ses_domain_identity_verification.domain_verification) == 1 && length(aws_route53_record.ses_dkim) == 3
    error_message = "Expected SES verification and DKIM DNS records when SES config is enabled."
  }

  assert {
    condition     = length(aws_route53_record.ses_spf) == 1 && length(aws_route53_record.ses_dmarc) == 1 && length(aws_route53_record.ses_mail_from_mx) == 1 && length(aws_route53_record.ses_mail_from_txt) == 1
    error_message = "Expected SPF, DMARC, and MAIL FROM DNS records when SES config is enabled."
  }

}