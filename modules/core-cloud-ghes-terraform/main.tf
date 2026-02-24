data "aws_caller_identity" "current" {}

data "aws_iam_role" "instance_management_role" {
  count = var.enable_instance_role ? 0 : 1
  name  = "ghes-instance-management-role"
}

resource "aws_iam_instance_profile" "instance_management_profile" {
  name = "ghes-instance-management-profile"
  role = var.enable_instance_role ? aws_iam_role.instance_management_role[0].name : data.aws_iam_role.instance_management_role[0].name
}


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

resource "aws_iam_role_policy_attachment" "ssm_logging_policy_attachment" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.ssm_logging_policy_name}"
}

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

resource "aws_iam_role_policy_attachment" "ssm_parameter_policy_attachment" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = aws_iam_policy.ssm_parameter_access[0].arn
}

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


resource "aws_iam_role_policy_attachment" "backup_host_s3_access_attachment" {
  count      = var.enable_instance_role ? 1 : 0
  role       = aws_iam_role.instance_management_role[0].name
  policy_arn = aws_iam_policy.backup_host_s3_access[0].arn
}

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

resource "aws_vpc_security_group_ingress_rule" "nlb_all_traffic_ingress" {
  for_each          = aws_security_group.nlb_sg
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "nlb_sg_outbound" {
  for_each          = aws_security_group.nlb_sg
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

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

resource "aws_vpc_security_group_ingress_rule" "primary_allow_tcp_from_secondary_ha" {
  security_group_id            = aws_security_group.github_sg["1"].id
  from_port                    = 122
  to_port                      = 122
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.github_sg["2"].id
}

resource "aws_vpc_security_group_ingress_rule" "secondary_allow_tcp_from_primary_ha" {
  security_group_id            = aws_security_group.github_sg["2"].id
  from_port                    = 122
  to_port                      = 122
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.github_sg["1"].id
}

resource "aws_vpc_security_group_ingress_rule" "primary_allow_udp_from_secondary_ha" {
  security_group_id            = aws_security_group.github_sg["1"].id
  from_port                    = 1194
  to_port                      = 1194
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.github_sg["2"].id
}

resource "aws_vpc_security_group_ingress_rule" "secondary_allow_udp_from_primary_ha" {
  security_group_id            = aws_security_group.github_sg["2"].id
  from_port                    = 1194
  to_port                      = 1194
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.github_sg["1"].id
}

resource "aws_vpc_security_group_egress_rule" "sg_outbound" {
  for_each          = aws_security_group.github_sg
  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

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

  user_data = <<-EOF
  #!/bin/bash
  export DEBIAN_FRONTEND=noninteractive

  sudo apt-get update -y
  sudo apt-get install -y docker.io wget curl unzip jq awscli

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

resource "aws_security_group" "backup_host_sg" {
  name        = "github-backup-host-sg"
  description = "Security group for the backup host"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name = "github-backup-host-sg"
    },
    var.common_tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "nlb_ssh_122_from_backup_host" {
  for_each                     = aws_security_group.nlb_sg
  security_group_id            = each.value.id
  from_port                    = 122
  to_port                      = 122
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backup_host_sg.id
}

resource "aws_vpc_security_group_egress_rule" "backup_host_egress_rule" {
  security_group_id = aws_security_group.backup_host_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}


resource "aws_instance" "backup_host" {
  ami                    = var.backup_host_ami_id
  instance_type          = var.backup_host_instance_type
  subnet_id              = element(var.private_subnet_ids, 0)
  vpc_security_group_ids = [aws_security_group.backup_host_sg.id]
  key_name               = var.key_name

  associate_public_ip_address = var.public_ip

  iam_instance_profile = aws_iam_instance_profile.instance_management_profile.name

  root_block_device {
    volume_size = var.backup_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive

    sudo apt-get update -y
    sudo apt-get install -y docker.io wget curl unzip jq awscli

    sudo usermod -aG docker ubuntu

    newgrp docker

    # Check if SSM agent is installed, enable and start it if needed
    if ! systemctl list-units --full -all | grep -q "amazon-ssm-agent.service"; then
      wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
      sudo dpkg -i amazon-ssm-agent.deb
    fi

    if ! systemctl is-enabled amazon-ssm-agent &>/dev/null; then
      sudo systemctl enable amazon-ssm-agent
    fi

    if ! systemctl is-active --quiet amazon-ssm-agent; then
      sudo systemctl start amazon-ssm-agent
    fi

    # Modify SSM agent to run as ubuntu user
    echo '{
      "RunAsUser": "ubuntu"
    }' | sudo tee /etc/amazon/ssm/amazon-ssm-agent.json

    # Restart SSM agent to apply the changes
    sudo systemctl restart amazon-ssm-agent

    # Install CloudWatch agent
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    sudo dpkg -i amazon-cloudwatch-agent.deb

    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config -m ec2 -c ssm:${var.cloudwatch_config} -s

    sudo systemctl enable amazon-cloudwatch-agent
    sudo systemctl start amazon-cloudwatch-agent

    # Authenticate with AWS ECR
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${var.ecr_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com
    docker pull ${var.github_backup_image}
  
    chown ubuntu:ubuntu /home/ubuntu/.ssh
    echo '${var.ssh_private_key}' > /home/ubuntu/.ssh/github_backup_key
    
    sed -i 's/-----BEGIN RSA PRIVATE KEY----- /-----BEGIN RSA PRIVATE KEY-----\n/' /home/ubuntu/.ssh/github_backup_key

    chown ubuntu:ubuntu /home/ubuntu/.ssh/github_backup_key
    chmod 600 /home/ubuntu/.ssh/github_backup_key
   
    sudo -u ubuntu docker run -d \
      --name github-backup \
      --restart always \
      -v /home/ubuntu/backup-data:/data \
      -v /home/ubuntu/.ssh/github_backup_key:/root/.ssh/github_backup_key \
      -e GHE_HOSTNAME="${var.ghe_hostname}" \
      -e GHE_EXTRA_SSH_OPTS="-i /root/.ssh/github_backup_key" \
      -e S3_BUCKET="${var.s3_bucket}" \
      "${var.github_backup_image}"
  EOF

  tags = merge(
    {
      Name        = "github-enterprise-server-backup-host",
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

resource "aws_eip" "backup_eip" {
  count    = var.public_eip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.backup_host.id

  tags = merge(
    {
      Name = "github-backup-host-eip",
    },
    var.common_tags
  )
}

# Route53 records
data "aws_route53_zone" "selected" {
  for_each = length(var.route53_zone_name) > 0 ? { "selected" = var.route53_zone_name } : {}

  name         = each.value
  private_zone = false
}

resource "aws_route53_record" "github_a_record" {
  for_each = length(var.route53_zone_name) > 0 && length(var.route53_record_name) > 0 ? aws_lb.nlb : {}

  zone_id = data.aws_route53_zone.selected["selected"].zone_id
  name    = var.route53_record_name
  type    = "A"

  weighted_routing_policy {
    weight = each.key == "1" ? var.primary_weight : var.secondary_weight
  }

  set_identifier = "server-${each.key}"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "github_wildcard_record" {
  for_each = length(var.route53_zone_name) > 0 && length(var.route53_record_name) > 0 ? aws_lb.nlb : {}

  zone_id = data.aws_route53_zone.selected["selected"].zone_id
  name    = "*.${var.route53_record_name}"
  type    = "A"

  weighted_routing_policy {
    weight = each.key == "1" ? var.primary_weight : var.secondary_weight
  }

  set_identifier = "wildcard-${each.key}"

  alias {
    name                   = each.value.dns_name
    zone_id                = each.value.zone_id
    evaluate_target_health = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Monitoring
locals {
  instance_ids = merge(
    { for k, v in aws_instance.github_instance : "github-${k}" => v.id },
    { "backup-host" = aws_instance.backup_host.id }
  )
}

resource "aws_sns_topic" "cloudwatch_alarm_topic" {
  name              = "github-${var.environment}-cloudwatch-alarms"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "alarm_subscription" {
  topic_arn = aws_sns_topic.cloudwatch_alarm_topic.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

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
resource "aws_ses_domain_identity" "ses_domain" {
  count  = var.create_ses_config ? 1 : 0
  domain = var.ses_domain_name
}

resource "aws_ses_domain_dkim" "dkim" {
  count  = var.create_ses_config ? 1 : 0
  domain = aws_ses_domain_identity.ses_domain[0].domain
}

resource "aws_ses_domain_mail_from" "mail_from" {
  count = var.create_ses_config ? 1 : 0

  domain           = aws_ses_domain_identity.ses_domain[0].domain
  mail_from_domain = "mailfrom.${aws_ses_domain_identity.ses_domain[0].domain}"
}

resource "aws_route53_record" "ses_verification" {
  count   = var.create_ses_config ? 1 : 0
  zone_id = data.aws_route53_zone.selected["selected"].zone_id
  name    = "_amazonses.${var.ses_domain_name}"
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.ses_domain[0].verification_token]
}

resource "aws_ses_domain_identity_verification" "domain_verification" {
  count  = var.create_ses_config ? 1 : 0
  domain = aws_ses_domain_identity.ses_domain[0].id

  depends_on = [aws_route53_record.ses_verification]
}

resource "aws_route53_record" "ses_dkim" {
  count           = var.create_ses_config ? 3 : 0
  zone_id         = data.aws_route53_zone.selected["selected"].zone_id
  name            = "${element(aws_ses_domain_dkim.dkim[0].dkim_tokens, count.index)}._domainkey.${var.ses_domain_name}"
  type            = "CNAME"
  ttl             = "600"
  records         = ["${element(aws_ses_domain_dkim.dkim[0].dkim_tokens, count.index)}.dkim.amazonses.com"]
  allow_overwrite = true
}

resource "aws_route53_record" "ses_spf" {
  count   = var.create_ses_config ? 1 : 0
  zone_id = data.aws_route53_zone.selected["selected"].zone_id
  name    = var.ses_domain_name
  type    = "TXT"
  ttl     = "600"
  records = ["v=spf1 include:amazonses.com -all"]
}

resource "aws_route53_record" "ses_dmarc" {
  count   = var.create_ses_config ? 1 : 0
  zone_id = data.aws_route53_zone.selected["selected"].zone_id
  name    = "_dmarc.${var.ses_domain_name}"
  type    = "TXT"
  ttl     = "600"
  records = ["v=DMARC1;p=reject;sp=reject;rua=mailto:dmarc-rua@dmarc.service.gov.uk"]
}

resource "aws_route53_record" "ses_mail_from_mx" {
  count   = var.create_ses_config ? 1 : 0
  zone_id = data.aws_route53_zone.selected["selected"].zone_id
  name    = aws_ses_domain_mail_from.mail_from[0].mail_from_domain
  type    = "MX"
  ttl     = "600"
  records = ["10 feedback-smtp.eu-west-2.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_txt" {
  count   = var.create_ses_config ? 1 : 0
  zone_id = data.aws_route53_zone.selected["selected"].zone_id
  name    = aws_ses_domain_mail_from.mail_from[0].mail_from_domain
  type    = "TXT"
  ttl     = "600"
  records = ["v=spf1 include:amazonses.com -all"]
}
