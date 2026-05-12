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
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "cost-centre", "") == "CC1000"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "cost-centre", "") == "CC1000"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "cost-centre", "") == "CC1000"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "cost-centre", "") == "CC1000"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "cost-centre", "") == "CC1000"])
    )
    error_message = "cost-centre tag must match expected value on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "account-code", "") == "AC1000"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "account-code", "") == "AC1000"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "account-code", "") == "AC1000"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "account-code", "") == "AC1000"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "account-code", "") == "AC1000"])
    )
    error_message = "account-code tag must match expected value on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "portfolio-id", "") == "PF1000"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "portfolio-id", "") == "PF1000"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "portfolio-id", "") == "PF1000"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "portfolio-id", "") == "PF1000"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "portfolio-id", "") == "PF1000"])
    )
    error_message = "portfolio-id tag must match expected value on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "project-id", "") == "PR1000"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "project-id", "") == "PR1000"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "project-id", "") == "PR1000"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "project-id", "") == "PR1000"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "project-id", "") == "PR1000"])
    )
    error_message = "project-id tag must match expected value on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "service-id", "") == "SV1000"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "service-id", "") == "SV1000"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "service-id", "") == "SV1000"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "service-id", "") == "SV1000"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "service-id", "") == "SV1000"])
    )
    error_message = "service-id tag must match expected value on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "environment-type", "") == "test"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "environment-type", "") == "test"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "environment-type", "") == "test"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "environment-type", "") == "test"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "environment-type", "") == "test"])
    )
    error_message = "environment-type tag must match expected value on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "owner-business", "") == "test"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "owner-business", "") == "test"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "owner-business", "") == "test"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "owner-business", "") == "test"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "owner-business", "") == "test"])
    )
    error_message = "owner-business tag must match expected value on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "budget-holder", "") == "testteam"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "budget-holder", "") == "testteam"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "budget-holder", "") == "testteam"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "budget-holder", "") == "testteam"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "budget-holder", "") == "testteam"])
    )
    error_message = "budget-holder tag must match expected value on tagged resources"
  }

  assert {
    condition = (
      alltrue([for _, instance in aws_instance.github_instance : lookup(instance.tags, "source-repo", "") == "Home-Office-Digital/core-cloud-github-enterprise-terraform"]) &&
      alltrue([for _, nlb in aws_lb.nlb : lookup(nlb.tags, "source-repo", "") == "Home-Office-Digital/core-cloud-github-enterprise-terraform"]) &&
      alltrue([for _, tg in aws_lb_target_group.tg : lookup(tg.tags, "source-repo", "") == "Home-Office-Digital/core-cloud-github-enterprise-terraform"]) &&
      alltrue([for _, sg in aws_security_group.github_sg : lookup(sg.tags, "source-repo", "") == "Home-Office-Digital/core-cloud-github-enterprise-terraform"]) &&
      alltrue([for _, sg in aws_security_group.nlb_sg : lookup(sg.tags, "source-repo", "") == "Home-Office-Digital/core-cloud-github-enterprise-terraform"])
    )
    error_message = "source-repo tag must match expected value on tagged resources"
  }
}
