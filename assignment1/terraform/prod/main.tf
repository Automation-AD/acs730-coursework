terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    bucket       = "acs730-tfstate-077932765602"
    key          = "assignment1/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Course      = "ACS730"
      Assignment  = "assignment1"
      Environment = "prod"
      Owner       = var.owner
    }
  }
}

variable "owner" {
  description = "Seneca username."
  type        = string
  default     = "adamaj1"
}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

module "webapp" {
  source = "../modules/webapp"

  environment         = "prod"
  owner               = var.owner
  vpc_cidr            = "10.30.0.0/16"
  ami_id              = data.aws_ssm_parameter.al2023.value
  instance_type       = "t3.micro"
  db_password_param   = "/acs730/assignment1/prod/db_password"
  cpu_alarm_threshold = 80
}
