terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend S3 com State Locking via DynamoDB
  backend "s3" {
    bucket         = "autoreparos-terraform-state-backend"
    key            = "database/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "autoreparos-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AutoReparos"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "Grupo78-PosTech-15SOAT/AutoReparos.Infra.Database"
      Fase        = "Fase-3"
    }
  }
}
