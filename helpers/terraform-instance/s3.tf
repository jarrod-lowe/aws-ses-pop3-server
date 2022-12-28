data "aws_caller_identity" "current" {}

# Create an S3 bucket
resource "aws_s3_bucket" "my_bucket" {
  bucket_prefix = "${var.project}-email-code-"
  force_destroy = true
}

# Enable versioning for the S3 bucket
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access to the S3 bucket and its contents
resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

## Set up bucket logging to another bucket
#resource "aws_s3_bucket_logging" "logging" {
#  bucket = aws_s3_bucket.my_bucket.id
#
#  target_bucket = "my-log-bucket"
#  target_prefix = "my-logs/"
#}

# Set up a lifecycle rule to automatically delete old versions of objects
resource "aws_s3_bucket_lifecycle_configuration" "lifecycle_rule" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"
    expiration {
      days = 30
    }
  }
}

# Enable default encryption for all objects stored in the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Define an IAM policy document that allows only the IAM role and the AdministratorAccess role to access the S3 bucket
data "aws_iam_policy_document" "bucket_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ec2_role.arn]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.my_bucket.arn}/*"]
  }

  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current.account_id]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.my_bucket.arn,
      "${aws_s3_bucket.my_bucket.arn}/*",
    ]
  }
}

# Create a resource policy that allows only the IAM role and the AdministratorAccess role to access the S3 bucket
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.my_bucket.id

  policy = data.aws_iam_policy_document.bucket_policy.json
}
