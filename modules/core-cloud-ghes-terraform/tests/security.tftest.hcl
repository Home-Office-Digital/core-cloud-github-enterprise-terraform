mock_provider "aws" {}

run "security_test" {
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
    condition     = length(aws_vpc_security_group_ingress_rule.nlb_all_traffic_ingress) == 2 && alltrue([for _, rule in aws_vpc_security_group_ingress_rule.nlb_all_traffic_ingress : rule.ip_protocol == "-1" && rule.cidr_ipv4 == "10.0.0.0/16"])
    error_message = "Expected VPC-wide all-traffic ingress on both NLB security groups."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.primary_allow_tcp_from_secondary_ha.ip_protocol == "tcp" && aws_vpc_security_group_ingress_rule.primary_allow_tcp_from_secondary_ha.from_port == 122 && aws_vpc_security_group_ingress_rule.secondary_allow_tcp_from_primary_ha.ip_protocol == "tcp" && aws_vpc_security_group_ingress_rule.secondary_allow_tcp_from_primary_ha.from_port == 122 && aws_vpc_security_group_ingress_rule.primary_allow_udp_from_secondary_ha.ip_protocol == "udp" && aws_vpc_security_group_ingress_rule.primary_allow_udp_from_secondary_ha.from_port == 1194 && aws_vpc_security_group_ingress_rule.secondary_allow_udp_from_primary_ha.ip_protocol == "udp" && aws_vpc_security_group_ingress_rule.secondary_allow_udp_from_primary_ha.from_port == 1194
    error_message = "Expected HA replication rules to enforce TCP 122 and UDP 1194 in both directions."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.sg_outbound) == 2 && alltrue([for _, rule in aws_vpc_security_group_egress_rule.sg_outbound : rule.ip_protocol == "-1" && rule.cidr_ipv4 == "0.0.0.0/0"])
    error_message = "Expected all GHES security groups to allow outbound traffic to 0.0.0.0/0."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.nlb_sg_outbound) == 2 && alltrue([for _, rule in aws_vpc_security_group_egress_rule.nlb_sg_outbound : rule.ip_protocol == "-1" && rule.cidr_ipv4 == "0.0.0.0/0"])
    error_message = "Expected all NLB security groups to allow outbound traffic to 0.0.0.0/0."
  }

  assert {
    condition     = length(aws_eip.github_eip) == 0
    error_message = "Expected no EIPs when public_eip is false."
  }
}
