mock_provider "aws" {
  mock_resource "aws_instance" {
    defaults = {
      id = "i-0backuphostmock"
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
    backup_host_ami_id      = "ami-0fedcba9876543210"
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
    condition     = output.vpc_id == "vpc-1234567890abcdef0"
    error_message = "Output vpc_id did not match the provided input."
  }
}