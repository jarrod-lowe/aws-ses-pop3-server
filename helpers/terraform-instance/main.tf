provider "aws" {
  default_tags {
    tags = {
      Project = var.project
    }
  }
}

terraform {
  backend "s3" {
    key    = "pop3.tfstate"
  }
}
