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
    key          = "assignment1/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    ec2        = var.localstack_endpoint
    ssm        = var.localstack_endpoint
    cloudwatch = var.localstack_endpoint
    sts        = var.localstack_endpoint
    s3         = var.localstack_endpoint
  }

  default_tags {
    tags = {
      Course      = "ACS730"
      Assignment  = "assignment1"
      Environment = "dev"
      Owner       = var.owner
    }
  }
}

variable "owner" {
  description = "Seneca username."
  type        = string
  default     = "adamaj1"
}

variable "localstack_endpoint" {
  description = "Where LocalStack listens."
  type        = string
  default     = "http://localhost:4566"
}

data "aws_caller_identity" "current" {}

module "webapp" {
  source = "../modules/webapp"

  environment         = "dev"
  owner               = var.owner
  vpc_cidr            = "10.10.0.0/16"
  ami_id              = "ami-0c02fb55956c7d316"
  instance_type       = "t3.micro"
  db_password_param   = "/acs730/assignment1/dev/db_password"
  cpu_alarm_threshold = 95
}
