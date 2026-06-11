output "vpc_id" {
  value = var.vpc_id
}

output "subnet_ids" {
  value = var.private_subnet_ids
}

output "github_instance_ids" {
  description = "IDs of the GitHub Enterprise instances"
  value       = { for k, v in aws_instance.github_instance : k => v.id }
}

output "nlb_arns" {
  description = "ARNs of the Network Load Balancers"
  value       = { for k, v in aws_lb.nlb : k => v.arn }
}

output "route53_zone_id" {
  value = length(var.route53_zone_name) > 0 ? data.aws_route53_zone.selected[0].zone_id : "Zone not managed by Terraform"
}

output "ghes_record_fqdn" {
  description = "Configured GHES hostname FQDN"
  value       = length(var.route53_zone_name) > 0 && length(var.route53_record_name) > 0 ? "${var.route53_record_name[0]}.${var.route53_zone_name[0]}" : null
}

output "ghes_wildcard_record_fqdn" {
  description = "Configured GHES wildcard hostname FQDN"
  value       = length(var.route53_zone_name) > 0 && length(var.route53_record_name) > 0 ? "*.${var.route53_record_name[0]}.${var.route53_zone_name[0]}" : null
}

output "ses_domain_verification_status" {
  description = "The verification status of the SES domain"
  value       = var.create_ses_config ? aws_ses_domain_identity_verification.domain_verification[0].id : null
}

output "ses_dkim_tokens" {
  description = "The DKIM tokens for the domain"
  value       = var.create_ses_config ? aws_ses_domain_dkim.dkim[0].dkim_tokens : null
}