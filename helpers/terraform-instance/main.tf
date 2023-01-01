terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.24.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Project = var.project
    }
  }
}

terraform {
  backend "s3" {
    key = "pop3.tfstate"
  }
}
