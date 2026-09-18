# core-cloud-github-enterprise-terraform-module

## Module Usage

```hcl
module "github_enterprise" {
  source                = "git::https://github.com/UKHomeOffice/core-cloud-github-enterprise-terraform?ref=v1.6.0"

  ssm_logging_policy_name = "ssm-logging-policy"
  s3_bucket               = "ghes-backup-bucket-name"
  vpc_id                  = "vpc-0123456789"
  vpc_cidr                = "10.0.0.0/16"
  allowed_cidr_ingress    = "10.0.0.0/16"
  use_private_subnets     = true
  public_subnet_ids       = ["subnet-id", "subnet-id"]
  private_subnet_ids      = ["subnet-id", "subnet-id"]
  ami_id                  = "ami-id"
  instance_type           = "r5.xlarge"
  key_name                = "my-ssh-key"
  ghe_hostname            = "ghes.ho.com"
  slack_webhook_url       = "https://hooks.slack.com/services/xxx/yyy/zzz"
  root_volume_size        = 100
  ebs_volume_size         = 500
  backup_root_volume_size = 30
  public_ip               = false
  public_eip              = false
  cloudwatch_config       = "AmazonCloudWatch-github-enterprise-config"
  sns_email               = "alerts@ho.com"
  environment             = "test"
  route53_zone_name       = "ho.com"
  route53_record_name     = "ghes.ho.com"
  primary_weight          = 100
  secondary_weight        = 0
  create_ses_config       = true
  ses_domain_name         = "email.prelive.ci.core.homeoffice.gov.uk"
  enable_instance_role    = false

  common_tags = {
    "cost-centre" = "CC1000"
    "environment" = "test"
  }

  # Optional: only needed if provisioning the Entra SCIM weighted DNS record
  entra_zone_name   = "ho.com"
  entra_record_name = "scim.ho.com"
  entra_records = {
    "primary" = {
      dns_name = "alb-primary.eu-west-2.elb.amazonaws.com"
      zone_id  = "Z1234567890ABC"
      weight   = 100
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ami_id"></a> [ami\_id](#input\_ami_id) | AMI ID for the GitHub Enterprise Server instances | `string` | n/a | yes |
| <a name="input_allowed_cidr_ingress"></a> [allowed\_cidr\_ingress](#input\_allowed_cidr_ingress) | CIDR blocks allowed for ingress | `string` | n/a | yes |
| <a name="input_backup_root_volume_size"></a> [backup\_root_volume_size](#input\_backup_root_volume_size) | Size of the root EBS volume for the backup host in GB | `number` | n/a | yes |
| <a name="input_cloudwatch_config"></a> [cloudwatch\_config](#input\_cloudwatch_config) | SSM parameter for CloudWatch config | `string` | n/a | yes |
| <a name="input_common_tags"></a> [common\_tags](#input\_common_tags) | Common tags to apply to all taggable resources | `map(string)` | `{}` | no |
| <a name="input_ebs_volume_size"></a> [ebs\_volume_size](#input_ebs_volume_size) | Size of the attached EBS data volume in GB | `number` | n/a | yes |
| <a name="input_enable_instance_role"></a> [enable\_instance\_role](#input\_enable_instance_role) | Whether to create the instance management IAM role, rather than reuse an existing one | `bool` | `false` | no |
| <a name="input_entra_record_name"></a> [entra\_record\_name](#input\_entra_record_name) | FQDN for the Entra SCIM weighted record | `string` | `""` | no |
| <a name="input_entra_records"></a> [entra\_records](#input\_entra_records) | Cross-account Entra ALB targets by id, each with `dns_name`, `zone_id`, and `weight` | `map(object({...}))` | `{}` | no |
| <a name="input_entra_zone_name"></a> [entra\_zone\_name](#input\_entra_zone_name) | Public hosted zone hosting the Entra SCIM weighted record. Empty = skip | `string` | `""` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., dev, prod) | `string` | n/a | yes |
| <a name="input_ghe_hostname"></a> [ghe\_hostname](#input\_ghe_hostname) | GitHub Enterprise hostname, used by the certificate renewal script | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input_instance_type) | EC2 instance type for GitHub Enterprise Server | `string` | `"r5.2xlarge"` | no |
| <a name="input_key_name"></a> [key_name](#input_key_name) | SSH key name for the instances | `string` | n/a | yes |
| <a name="input_port_to_name_map"></a> [port\_to\_name_map](#input\_port_to_name_map) | Map of ports to target group name suffixes, used to build NLB listeners/target groups | `map(string)` | see `variables.tf` | no |
| <a name="input_primary_weight"></a> [primary\_weight](#input_primary_weight) | Weight for the primary Route53 record | `number` | `100` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet_ids](#input_private_subnet_ids) | List of private subnet IDs for the NLB | `list(string)` | n/a | yes |
| <a name="input_public_eip"></a> [public\_eip](#input\_public_eip) | Whether to allocate and associate an Elastic IP per instance | `bool` | `false` | no |
| <a name="input_public_ip"></a> [public\_ip](#input\_public_ip) | Whether to assign a public IP to the instances | `bool` | `false` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet_ids](#input_public_subnet_ids) | List of public subnet IDs for the NLB | `list(string)` | `[]` | no |
| <a name="input_route53_record_name"></a> [route53\_record_name](#input_route53_record_name) | Route53 record name for GitHub Enterprise | `string` | `""` | no |
| <a name="input_route53_zone_name"></a> [route53\_zone_name](#input_route53_zone_name) | Route53 zone name for DNS records | `string` | `""` | no |
| <a name="input_root_volume_size"></a> [root\_volume_size](#input_root_volume_size) | Size of the root EBS volume in GB | `number` | n/a | yes |
| <a name="input_secondary_weight"></a> [secondary\_weight](#input_secondary_weight) | Weight for the secondary Route53 record | `number` | `0` | no |
| <a name="input_s3_bucket"></a> [s3_bucket](#input_s3_bucket) | Name of the S3 bucket for backups | `string` | n/a | yes |
| <a name="input_slack_webhook_url"></a> [slack\_webhook\_url](#input\_slack_webhook_url) | Slack incoming webhook URL for certificate renewal notifications | `string` | n/a | yes |
| <a name="input_sns_email"></a> [sns_email](#input_sns_email) | Email to receive CloudWatch alarm notifications | `string` | n/a | yes |
| <a name="input_ssm_logging_policy_name"></a> [ssm\_logging\_policy_name](#input_ssm_logging_policy_name) | Name of the SSM logging policy | `string` | n/a | yes |
| <a name="input_use_private_subnets"></a> [use_private_subnets](#input_use_private_subnets) | Flag to use private subnets for the NLB | `bool` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc_cidr) | CIDR block of the VPC | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc_id](#input_vpc_id) | ID of the VPC where resources are deployed | `string` | n/a | yes |
| <a name="input_create_ses_config"></a> [create\_ses\_config](#input\_create_ses_config) | Flag to create SES configuration | `bool` | `false` | no |
| <a name="input_ses_domain_name"></a> [ses\_domain\_name](#input\_ses_domain_name) | Domain name for SES configuration | `string` | `""` | no |