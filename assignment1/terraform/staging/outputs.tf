output "account_id" {
  description = "AWS account this run talked to. 000000000000 means LocalStack."
  value       = data.aws_caller_identity.current.account_id
}

output "web_url" {
  value = module.webapp.web_url
}

output "web_instance_id" {
  value = module.webapp.web_instance_id
}

output "vpc_id" {
  value = module.webapp.vpc_id
}

output "cpu_alarm_name" {
  value = module.webapp.cpu_alarm_name
}

output "db_password_length" {
  value = module.webapp.db_password_length
}
