mock_provider "aws" {}

run "security_test" {
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
    condition     = alltrue([for _, instance in aws_instance.github_instance : instance.root_block_device[0].encrypted == true && instance.root_block_device[0].delete_on_termination == false])
    error_message = "Expected root volumes to be encrypted and retained on termination."
  }

  assert {
    condition     = alltrue(flatten([for _, instance in aws_instance.github_instance : [for block in instance.ebs_block_device : block.encrypted == true]]))
    error_message = "Expected all attached EBS data volumes to be encrypted."
  }

  assert {
    condition     = alltrue([for _, instance in aws_instance.github_instance : instance.metadata_options[0].http_tokens == "required" && instance.metadata_options[0].http_put_response_hop_limit == 1])
    error_message = "Expected IMDSv2 hardening on all GHES instances."
  }

  assert {
    condition     = alltrue([for _, rule in aws_vpc_security_group_ingress_rule.github_ingress_rules : rule.ip_protocol == "tcp" && rule.from_port == rule.to_port])
    error_message = "Expected GHES ingress rules to be TCP and restricted to specific single ports."
  }

  assert {
    condition     = alltrue([for _, rule in aws_vpc_security_group_ingress_rule.nlb_ingress_rule : rule.cidr_ipv4 == "10.0.0.0/16"])
    error_message = "Expected NLB ingress rules to be restricted to allowed CIDR ingress."
  }

  assert {
    condition     = length(aws_eip.github_eip) == 0
    error_message = "Expected no EIPs when public_eip is false."
  }
}
