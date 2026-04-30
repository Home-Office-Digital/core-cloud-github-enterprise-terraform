mock_provider "aws" {}

run "tagging_test" {
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
    common_tags = {
      Environment = "test"
      Owner       = "platform"
      CostCentre  = "cc-ghes"
    }
  }

  assert {
    condition     = alltrue([for _, instance in aws_instance.github_instance : instance.tags["Environment"] == "test" && instance.tags["Owner"] == "platform" && instance.tags["CostCentre"] == "cc-ghes" && instance.tags["MonitoredBy"] == "Dynatrace"])
    error_message = "Expected GHES instances to include merged common tags and MonitoredBy tag."
  }

  assert {
    condition     = alltrue([for _, nlb in aws_lb.nlb : nlb.tags["Environment"] == "test" && nlb.tags["Owner"] == "platform"])
    error_message = "Expected NLBs to include common tags."
  }

  assert {
    condition     = alltrue([for _, sg in aws_security_group.github_sg : sg.tags["Environment"] == "test" && sg.tags["Owner"] == "platform"])
    error_message = "Expected GHES security groups to include common tags."
  }
}
