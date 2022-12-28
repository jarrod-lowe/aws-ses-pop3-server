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
