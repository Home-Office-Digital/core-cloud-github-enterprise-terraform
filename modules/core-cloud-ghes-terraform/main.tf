terraform {
  # Pin the Terraform and provider versions this module was written for.
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

// Read the current AWS account so policy ARNs can be built dynamically.
data "aws_caller_identity" "current" {}

// Look up an existing instance management role when we are not creating one here.
data "aws_iam_role" "instance_management_role" {
  count = var.enable_instance_role ? 0 : 1
  name  = "ghes-instance-management-role"
}

// Instance profile attached to both GHES nodes and the backup host.
resource "aws_iam_instance_profile" "instance_management_profile" {
  name = "ghes-instance-management-profile"
  role = var.enable_instance_role ? aws_iam_role.instance_management_role[0].name : data.aws_iam_role.instance_management_role[0].name
}


// Optional instance role created by this module when requested.
resource "aws_iam_role" "instance_management_role" {
  count = var.enable_instance_role ? 1 : 0
  name  = "github-instance-management-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

// Attach the logging policy that already exists in the AWS account.
resource "aws_iam_role_policy_attachment" "ssm_logging_policy_attachment" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.ssm_logging_policy_name}"
}

// Give the instance role the standard AWS-managed permissions it needs.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "route_53_policy" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

// Grant SSM parameter read access for the user data bootstrap scripts.
resource "aws_iam_policy" "ssm_parameter_access" {
  count = var.enable_instance_role ? 1 : 0
  name  = "ssm-parameter-access-policy"
  path  = "/"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ],
        Resource = "*"
      }
    ]
  })
}

// Attach the SSM parameter read policy to the instance role.
resource "aws_iam_role_policy_attachment" "ssm_parameter_policy_attachment" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = aws_iam_policy.ssm_parameter_access[0].arn
}

// Allow the backup host to read and write the S3 backup bucket.
resource "aws_iam_policy" "backup_host_s3_access" {
  count = var.enable_instance_role ? 1 : 0
  name  = "backup-host-s3-access-policy"
  path  = "/"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = "arn:aws:s3:::${var.s3_bucket}"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectAcl",
          "s3:PutObjectAcl"
        ],
        Resource = "arn:aws:s3:::${var.s3_bucket}/*"
      }
    ]
  })
}


// Attach the S3 backup policy to the instance role.
resource "aws_iam_role_policy_attachment" "backup_host_s3_access_attachment" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = aws_iam_policy.backup_host_s3_access[0].arn
}

// Create two NLB security groups, one for each GHES node and NLB.
resource "aws_security_group" "nlb_sg" {
  for_each    = { "1" = "nlb1", "2" = "nlb2" }
  name        = "github-enterprise-nlb-sg-${each.key}"
  description = "Security group for Github Enterprise Server NLB ${each.value}"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name = "github-enterprise-nlb-sg-${each.key}"
    },
    var.common_tags
  )
}

// Allow the configured application ports from the approved CIDR range.
resource "aws_vpc_security_group_ingress_rule" "nlb_ingress_rule" {
  for_each = {
    for pair in setproduct(keys(aws_security_group.nlb_sg), keys(var.port_to_name_map)) :
    "${pair[0]}-${pair[1]}" => {
      sg_key = pair[0]
      port   = pair[1]
    }
  }

  security_group_id = aws_security_group.nlb_sg[each.value.sg_key].id
  from_port         = tonumber(each.value.port)
  to_port           = tonumber(each.value.port)
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_cidr_ingress
}

// Allow any traffic between the NLB security groups and the VPC CIDR.
resource "aws_vpc_security_group_ingress_rule" "nlb_all_traffic_ingress" {
  for_each          = aws_security_group.nlb_sg
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

// Allow the NLBs to send traffic back out to the internet or AWS services.
resource "aws_vpc_security_group_egress_rule" "nlb_sg_outbound" {
  for_each          = aws_security_group.nlb_sg
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

// Create the two NLBs that front the two GHES instances.
resource "aws_lb" "nlb" {
  for_each           = aws_security_group.nlb_sg
  name               = "github-enterprise-nlb-${each.key}"
  internal           = var.use_private_subnets
  load_balancer_type = "network"
  subnets            = var.use_private_subnets ? var.private_subnet_ids : var.public_subnet_ids
  security_groups    = [each.value.id]

  tags = merge(
    {
      Name = "github-enterprise-nlb-${each.key}"
    },
    var.common_tags
  )
}

// Create a target group per NLB and application port.
resource "aws_lb_target_group" "tg" {
  for_each = {
    for pair in setproduct(keys(aws_lb.nlb), keys(var.port_to_name_map)) :
    "${pair[0]}-${pair[1]}" => {
      nlb_key = pair[0]
      port    = pair[1]
    }
  }

  name     = "tg-${each.value.nlb_key}-${var.port_to_name_map[each.value.port]}"
  port     = tonumber(each.value.port)
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }

  tags = merge(
    {
      Name = "tg-${each.value.nlb_key}-${var.port_to_name_map[each.value.port]}"
    },
    var.common_tags
  )
}

// Attach each NLB listener to the matching target group.
resource "aws_lb_listener" "nlb_listener" {
  for_each = {
    for pair in setproduct(keys(aws_lb.nlb), keys(var.port_to_name_map)) :
    "${pair[0]}-${pair[1]}" => {
      nlb_key = pair[0]
      port    = pair[1]
    }
  }

  load_balancer_arn = aws_lb.nlb[each.value.nlb_key].arn
  protocol          = "TCP"
  port              = tonumber(each.value.port)

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg["${each.value.nlb_key}-${each.value.port}"].arn
  }
}

// Register the GHES instances as targets behind the NLB target groups.
resource "aws_lb_target_group_attachment" "tg_attachment" {
  for_each = {
    for pair in setproduct(keys(aws_lb.nlb), keys(var.port_to_name_map)) :
    "${pair[0]}-${pair[1]}" => {
      nlb_key = pair[0]
      port    = pair[1]
    }
  }

  target_group_arn = aws_lb_target_group.tg["${each.value.nlb_key}-${each.value.port}"].arn
  target_id        = aws_instance.github_instance[each.value.nlb_key].id
  port             = tonumber(each.value.port)
}

// Security groups for the primary and secondary GHES instances.
resource "aws_security_group" "github_sg" {
  for_each    = { "1" = "primary", "2" = "secondary" }
  name        = "github-enterprise-server-sg-${each.key}"
  description = "Security group for GitHub Server ${each.value}"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name = "github-enterprise-server-sg-${each.key}"
    },
    var.common_tags
  )
}

// Allow the NLBs to reach the GHES application ports on each instance.
resource "aws_vpc_security_group_ingress_rule" "github_ingress_rules" {
  for_each = {
    for pair in setproduct(["1", "2"], keys(var.port_to_name_map)) :
    "${pair[0]}-${pair[1]}" => {
      instance_num = pair[0]
      port         = pair[1]
    }
  }

  security_group_id            = aws_security_group.github_sg[each.value.instance_num].id
  from_port                    = tonumber(each.value.port)
  to_port                      = tonumber(each.value.port)
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.nlb_sg[each.value.instance_num].id
}

// Permit the HA nodes to talk to each other over the required TCP ports.
resource "aws_vpc_security_group_ingress_rule" "primary_allow_tcp_from_secondary_ha" {
  security_group_id            = aws_security_group.github_sg["1"].id
  from_port                    = 122
  to_port                      = 122
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.github_sg["2"].id
}

// Reverse HA TCP rule from primary to secondary.
resource "aws_vpc_security_group_ingress_rule" "secondary_allow_tcp_from_primary_ha" {
  security_group_id            = aws_security_group.github_sg["2"].id
  from_port                    = 122
  to_port                      = 122
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.github_sg["1"].id
}

// Permit the HA nodes to talk to each other over the required UDP port.
resource "aws_vpc_security_group_ingress_rule" "primary_allow_udp_from_secondary_ha" {
  security_group_id            = aws_security_group.github_sg["1"].id
  from_port                    = 1194
  to_port                      = 1194
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.github_sg["2"].id
}

// Reverse HA UDP rule from primary to secondary.
resource "aws_vpc_security_group_ingress_rule" "secondary_allow_udp_from_primary_ha" {
  security_group_id            = aws_security_group.github_sg["2"].id
  from_port                    = 1194
  to_port                      = 1194
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.github_sg["1"].id
}

// Allow outbound traffic from the GHES instances.
resource "aws_vpc_security_group_egress_rule" "sg_outbound" {
  for_each          = aws_security_group.github_sg
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

// Primary and secondary GHES instances.
resource "aws_instance" "github_instance" {
  for_each               = aws_security_group.github_sg
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = element(var.private_subnet_ids, tonumber(each.key) - 1)
  vpc_security_group_ids = [each.value.id]

  associate_public_ip_address = var.public_ip

  iam_instance_profile = aws_iam_instance_profile.instance_management_profile.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = false
    encrypted             = true
  }

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_size           = var.ebs_volume_size
    volume_type           = "gp3"
    delete_on_termination = false
    encrypted             = true
  }

  # Pre-provision a second data disk for the secondary node so it can be promoted later.
  # The backup service is only configured on promotion, not while the node is a replica.

  ebs_block_device {
    device_name           = "/dev/sdc"
    volume_size           = var.backup_root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = false
  }

  user_data = <<-EOF
  #!/bin/bash
  export DEBIAN_FRONTEND=noninteractive

  sudo apt-get update -y
  sudo apt-get install -y docker.io wget curl unzip jq awscli nvme-cli

  # Install SSM agent if not already installed
  if ! systemctl list-units --full -all | grep -q "amazon-ssm-agent.service"; then
    wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
    sudo dpkg -i amazon-ssm-agent.deb
  fi

  # Enable and start SSM agent if not already enabled
  if ! systemctl is-enabled amazon-ssm-agent &>/dev/null; then
    sudo systemctl enable amazon-ssm-agent
  fi

  # Start SSM agent if not already active
  if ! systemctl is-active --quiet amazon-ssm-agent; then
    sudo systemctl start amazon-ssm-agent
  fi

  # Install CloudWatch agent if not already installed
  if ! systemctl list-units --full -all | grep -q "amazon-cloudwatch-agent.service"; then
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    sudo dpkg -i amazon-cloudwatch-agent.deb
  fi

  # Fetch CloudWatch config from SSM Parameter Store and start agent
  sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c ssm:${var.cloudwatch_config} -s

  sudo systemctl enable amazon-cloudwatch-agent
  sudo systemctl start amazon-cloudwatch-agent

  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  python3 -c "import zipfile; zipfile.ZipFile('/tmp/awscliv2.zip').extractall('/tmp/')"
  chmod +x /tmp/aws/install /tmp/aws/dist/aws
  sudo /tmp/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
  sudo chmod +x /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws
  rm -rf /tmp/awscliv2.zip /tmp/aws
  
  cat > /opt/cert-renewal.sh << 'CERTS'
  ${templatefile("${path.module}/templates/cert-renewal.sh.tpl", {
  ghes_hostname     = var.ghe_hostname
  slack_webhook_url = var.slack_webhook_url
})}
  CERTS

  chmod 700 /opt/cert-renewal.sh

  # Install cron job to run daily at 07:00 UTC
  cat > /etc/cron.d/ghes-cert-renewal << 'CRONFILE'
  SHELL=/bin/bash
  PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
  0 7 * * * root /opt/cert-renewal.sh >> /var/log/ghes-cert-renewal.log 2>&1
  CRONFILE

  chmod 644 /etc/cron.d/ghes-cert-renewal
  chown root:root /etc/cron.d/ghes-cert-renewal

  # Find the attached NVMe device that corresponds to /dev/sdc.
  get_nvme_device() {
    local target_name=$1
    for dev in /dev/nvme*n1; do
      # AWS stores the device name (e.g. /dev/sdc) in the vendor-specific data
      if nvme id-ctrl -v "$dev" | grep -q "$target_name"; then
        echo "$dev"
        return 0
      fi
    done
    return 1
  }

  # Wait for AWS to finish attaching the disk, then initialize the backup volume.
  TARGET_NAME="/dev/sdc"
  REAL_DEV=""
  while [ -z "$REAL_DEV" ]; do
    REAL_DEV=$(get_nvme_device "$TARGET_NAME")
    [ -z "$REAL_DEV" ] && sleep 2
  done
  if [ -f /etc/github/repl-state ] && [ "$(cat /etc/github/repl-state)" = "replica" ]; then
    echo "This instance is configured as a replica. So no backup configured as per github advice."
    exit 0
  fi

  # https://docs.github.com/en/enterprise-server@3.17/admin/backing-up-and-restoring-your-instance/backup-service-for-github-enterprise-server/configuring-the-backup-service
  /usr/local/share/enterprise/ghe-storage-init-backup "/dev/$REAL_DEV"
  
  EOF

tags = merge(
  {
    Name        = "github-enterprise-server-${each.key}",
    MonitoredBy = "Dynatrace"
  },
  var.common_tags
)

monitoring = true
metadata_options {
  http_tokens                 = "required" # Require token (IMDSv2 only)
  http_endpoint               = "enabled"  # Keep metadata endpoint enabled
  http_put_response_hop_limit = 1          # Limit hop count for PUT requests
}
}

// Optional public IPs for the GHES nodes.
resource "aws_eip" "github_eip" {
  for_each = var.public_eip ? aws_instance.github_instance : {}
  domain   = "vpc"
  instance = each.value.id

  tags = merge(
    {
      Name = "github-enterprise-server-eip-${each.key}"
    },
    var.common_tags
  )
}

# Route53 records
// Look up every configured hosted zone, and mark it private when its name contains internal.
data "aws_route53_zone" "selected" {
  for_each = { for zone_name in var.route53_zone_name : zone_name => zone_name }
  name         = each.value
  private_zone = can(regex("internal", lower(each.value))) ? true : false
}

locals {
  route53_primary_zone_name = length(var.route53_zone_name) > 0 ? var.route53_zone_name[0] : null

  route53_name_by_zone = zipmap(var.route53_zone_name, var.route53_record_name)

  route53_matrix = {
    for pair in setproduct(var.route53_zone_name, keys(aws_lb.nlb)) :
    "${pair[0]}|${pair[1]}" => {
      zone        = pair[0]
      lb_key      = pair[1]
      record_name = local.route53_name_by_zone[pair[0]]
    }
  }
}

// Weighted alias A records across both NLBs for each configured hosted zone.
resource "aws_route53_record" "github_a_record" {
  for_each = local.route53_matrix

  zone_id = data.aws_route53_zone.selected[each.value.zone].zone_id
  name    = each.value.record_name
  type    = "A"

  weighted_routing_policy {
    weight = each.value.lb_key == "1" ? var.primary_weight : var.secondary_weight
  }

  set_identifier = "server-${each.value.lb_key}"

  alias {
    name                   = aws_lb.nlb[each.value.lb_key].dns_name
    zone_id                = aws_lb.nlb[each.value.lb_key].zone_id
    evaluate_target_health = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

// Weighted wildcard records so subdomains resolve the same way as the base host.
resource "aws_route53_record" "github_wildcard_record" {
  for_each = local.route53_matrix

  zone_id = data.aws_route53_zone.selected[each.value.zone].zone_id
  name    = "*.${each.value.record_name}"
  type    = "A"

  weighted_routing_policy {
    weight = each.value.lb_key == "1" ? var.primary_weight : var.secondary_weight
  }

  set_identifier = "wildcard-${each.value.lb_key}"

  alias {
    name                   = aws_lb.nlb[each.value.lb_key].dns_name
    zone_id                = aws_lb.nlb[each.value.lb_key].zone_id
    evaluate_target_health = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Monitoring
// Build a simple map of instance IDs so we can create one alarm set per node and backup host.
locals {
  instance_ids = merge(
    { for k, v in aws_instance.github_instance : "github-${k}" => v.id }
  )
}

// Central SNS topic for all CloudWatch alarms.
resource "aws_sns_topic" "cloudwatch_alarm_topic" {
  name              = "github-${var.environment}-cloudwatch-alarms"
  kms_master_key_id = "alias/aws/sns"
}

// Email subscription for alarm notifications.
resource "aws_sns_topic_subscription" "alarm_subscription" {
  topic_arn = aws_sns_topic.cloudwatch_alarm_topic.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

// CPU alarm for each managed instance.
resource "aws_cloudwatch_metric_alarm" "cpu_usage_alarm" {
  for_each = local.instance_ids

  alarm_name          = "${var.environment}-cpu-usage-alarm-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "cpu_usage_active"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Alarm when CPU usage exceeds 75% on ${each.key} in ${var.environment} environment"
  dimensions = {
    InstanceId = each.value
  }
  alarm_actions = [aws_sns_topic.cloudwatch_alarm_topic.arn]
}

// Memory alarm for each managed instance.
resource "aws_cloudwatch_metric_alarm" "memory_usage_alarm" {
  for_each = local.instance_ids

  alarm_name          = "${var.environment}-memory-usage-alarm-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Alarm when memory usage exceeds 70% on ${each.key} in ${var.environment} environment"
  dimensions = {
    InstanceId = each.value
  }
  alarm_actions = [aws_sns_topic.cloudwatch_alarm_topic.arn]
}

// Disk alarm for each managed instance.
resource "aws_cloudwatch_metric_alarm" "disk_usage_alarm" {
  for_each = local.instance_ids

  alarm_name          = "${var.environment}-disk-usage-alarm-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm when disk usage exceeds 80% on ${each.key} in ${var.environment} environment"
  dimensions = {
    InstanceId = each.value
  }
  alarm_actions = [aws_sns_topic.cloudwatch_alarm_topic.arn]
}

# SES Domain Configuration
// Create and verify SES identity records only when SES setup is enabled.
resource "aws_ses_domain_identity" "ses_domain" {
  count  = var.create_ses_config ? 1 : 0
  domain = var.ses_domain_name
}

// Generate DKIM tokens for the SES domain.
resource "aws_ses_domain_dkim" "dkim" {
  count  = var.create_ses_config ? 1 : 0
  domain = aws_ses_domain_identity.ses_domain[0].domain
}

// Create the MAIL FROM subdomain used by SES.
resource "aws_ses_domain_mail_from" "mail_from" {
  count = var.create_ses_config && length(var.route53_zone_name) > 0 ? 1 : 0

  domain           = aws_ses_domain_identity.ses_domain[0].domain
  mail_from_domain = "mailfrom.${aws_ses_domain_identity.ses_domain[0].domain}"
}

// Publish the SES verification TXT record in the primary Route53 zone.
resource "aws_route53_record" "ses_verification" {
  count   = var.create_ses_config && length(var.route53_zone_name) > 0 ? 1 : 0
  zone_id = data.aws_route53_zone.selected[local.route53_primary_zone_name].zone_id
  name    = "_amazonses.${var.ses_domain_name}"
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.ses_domain[0].verification_token]
}

// Mark the SES domain as verified once the TXT record exists.
resource "aws_ses_domain_identity_verification" "domain_verification" {
  count  = var.create_ses_config && length(var.route53_zone_name) > 0 ? 1 : 0
  domain = aws_ses_domain_identity.ses_domain[0].id

  depends_on = [aws_route53_record.ses_verification]
}

// Publish the three DKIM CNAME records expected by SES.
resource "aws_route53_record" "ses_dkim" {
  count           = var.create_ses_config && length(var.route53_zone_name) > 0 ? 3 : 0
  zone_id         = data.aws_route53_zone.selected[local.route53_primary_zone_name].zone_id
  name            = "${element(aws_ses_domain_dkim.dkim[0].dkim_tokens, count.index)}._domainkey.${var.ses_domain_name}"
  type            = "CNAME"
  ttl             = "600"
  records         = ["${element(aws_ses_domain_dkim.dkim[0].dkim_tokens, count.index)}.dkim.amazonses.com"]
  allow_overwrite = true
}

// Publish SPF so the SES domain can send mail.
resource "aws_route53_record" "ses_spf" {
  count   = var.create_ses_config && length(var.route53_zone_name) > 0 ? 1 : 0
  zone_id = data.aws_route53_zone.selected[local.route53_primary_zone_name].zone_id
  name    = var.ses_domain_name
  type    = "TXT"
  ttl     = "600"
  records = ["v=spf1 include:amazonses.com -all"]
}

// Publish a DMARC policy for the SES domain.
resource "aws_route53_record" "ses_dmarc" {
  count   = var.create_ses_config && length(var.route53_zone_name) > 0 ? 1 : 0
  zone_id = data.aws_route53_zone.selected[local.route53_primary_zone_name].zone_id
  name    = "_dmarc.${var.ses_domain_name}"
  type    = "TXT"
  ttl     = "600"
  records = ["v=DMARC1;p=reject;sp=reject;rua=mailto:dmarc-rua@dmarc.service.gov.uk"]
}

// Publish the MX record that routes MAIL FROM traffic to SES.
resource "aws_route53_record" "ses_mail_from_mx" {
  count   = var.create_ses_config && length(var.route53_zone_name) > 0 ? 1 : 0
  zone_id = data.aws_route53_zone.selected[local.route53_primary_zone_name].zone_id
  name    = aws_ses_domain_mail_from.mail_from[0].mail_from_domain
  type    = "MX"
  ttl     = "600"
  records = ["10 feedback-smtp.eu-west-2.amazonses.com"]
}

// Publish the MAIL FROM TXT record so the subdomain is authorized.
resource "aws_route53_record" "ses_mail_from_txt" {
  count   = var.create_ses_config && length(var.route53_zone_name) > 0 ? 1 : 0
  zone_id = data.aws_route53_zone.selected[local.route53_primary_zone_name].zone_id
  name    = aws_ses_domain_mail_from.mail_from[0].mail_from_domain
  type    = "TXT"
  ttl     = "600"
  records = ["v=spf1 include:amazonses.com -all"]
}
