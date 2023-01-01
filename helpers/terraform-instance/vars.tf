variable "project" {
  description = "Name of the project"
  type        = string
  default     = "pop3"
}

variable "architecture" {
  description = "Architecture"
  type        = string
  default     = "arm64"
  #allowed_values = ["arm64", "x86_64"]
}

variable "tls_lambda_architecture" {
  description = "Architecture for TLS Lambda"
  type        = string
  default     = "arm64"
  #allowed_values = ["arm64", "x86_64"]
}

variable "tls_build_container" {
  description = "AWS Container for Python3 Lambda"
  type        = string
  default     = "amazon/aws-lambda-python:3.9.2022.12.28.07"
}

variable "ami_name" {
  description = "Regex for the AMI to use"
  type        = string
  default     = "amzn2-ami-hvm-2.0.????????.?-arm64-gp2"
}

variable "instance_type" {
  description = "Instance Type"
  type        = string
  default     = "t4g.nano"
}

variable "volume_type" {
  description = "EBS Volume type"
  type        = string
  default     = "gp3"
}

variable "volume_size" {
  description = "Size in GB of the volume"
  type        = number
  default     = 10
}

variable "mail_bucket" {
  # TODO: handle multiple mail buckets
  description = "Name of the S3 bucket the email is stored in"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to store logs for"
  type        = number
  default     = 14
}

variable "port" {
  # 2110 for non-TLS, 2995 for TLS
  description = "Port number to listen on"
  type        = number
  default     = 2110
}

variable "tls_key_rotation_days" {
  description = "Number of days after which to replace the TLS key"
  type        = number
  default     = 120
}

variable "tls_rotate_timeout" {
  description = "Timeout on the TLS rotation lambda"
  type        = number
  default     = 900
}

variable "external_code_dir" {
  description = "Source directory of the code on the host"
  type        = string
  default     = "/Users/jarrod/git/aws-ses-pop3-server"
}

variable "acme_email" {
  description = "Email address to register ACME account with"
  type        = string
}
