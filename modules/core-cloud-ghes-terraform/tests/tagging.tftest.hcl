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
      "cost-centre"      = "CC1000"
      "account-code"     = "AC1000"
      "portfolio-id"     = "PF1000"
      "project-id"       = "PR1000"
      "service-id"       = "SV1000"
      "environment-type" = "test"
      "owner-business"   = "test"
      "budget-holder"    = "testteam"
      "source-repo"      = "Home-Office-Digital/core-cloud-github-enterprise-terraform"
    }
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "cost-centre")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "cost-centre")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "cost-centre")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "cost-centre")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "cost-centre")])
    )
    error_message = "cost-centre tag must be present on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "account-code")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "account-code")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "account-code")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "account-code")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "account-code")])
    )
    error_message = "account-code tag must be present on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "portfolio-id")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "portfolio-id")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "portfolio-id")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "portfolio-id")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "portfolio-id")])
    )
    error_message = "portfolio-id tag must be present on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "project-id")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "project-id")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "project-id")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "project-id")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "project-id")])
    )
    error_message = "project-id tag must be present on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "service-id")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "service-id")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "service-id")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "service-id")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "service-id")])
    )
    error_message = "service-id tag must be present on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "environment-type")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "environment-type")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "environment-type")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "environment-type")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "environment-type")])
    )
    error_message = "environment-type tag must be present on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "owner-business")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "owner-business")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "owner-business")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "owner-business")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "owner-business")])
    )
    error_message = "owner-business tag must be present on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "budget-holder")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "budget-holder")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "budget-holder")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "budget-holder")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "budget-holder")])
    )
    error_message = "budget-holder tag must be present on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : contains(keys(instance.tags), "source-repo")]) &&
      alltrue([for _, nlb in aws_lb.nlb : contains(keys(nlb.tags), "source-repo")]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : contains(keys(tg.tags), "source-repo")]) &&
      alltrue([for _, sg in aws_security_group.github_sg : contains(keys(sg.tags), "source-repo")]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : contains(keys(sg.tags), "source-repo")])
    )
    error_message = "source-repo tag must be present on tagged resources"
  }
}
