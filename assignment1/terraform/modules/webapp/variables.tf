variable "environment" {
  description = "Environment name, used in every resource name and tag."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "owner" {
  description = "Seneca username, added to resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Two /24 public subnets are cut from it."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR, like 10.20.0.0/16."
  }
}

variable "ami_id" {
  description = "AMI for the web server. The caller looks it up."
  type        = string
}

variable "instance_type" {
  description = "Instance size for the web server."
  type        = string
  default     = "t3.micro"
  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "Only t3.micro or t3.small, the term budget is $50."
  }
}

variable "db_password_param" {
  description = "Name of the SSM SecureString parameter holding the placeholder db password."
  type        = string
}

variable "cpu_alarm_threshold" {
  description = "Average CPU percent that puts the alarm in ALARM."
  type        = number
  default     = 80
}
