# Create an IAM role that allows EC2 instances to assume it
resource "aws_iam_role" "ec2_role" {
  name = "${var.project}-ec2-role"

  assume_role_policy = data.aws_iam_policy_document.ec2_role_assume.json
}

data "aws_iam_policy_document" "ec2_role_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

# Define an IAM policy document that allows read/write access to the S3 bucket
data "aws_iam_policy_document" "policy" {
  statement {
    sid       = "InvokeLambda"
    actions   = ["lambda:Invoke"]
    resources = [aws_lambda_function.auth_proxy.arn]
  }
}

# Create an IAM policy that allows read/write access to the S3 bucket
resource "aws_iam_policy" "policy" {
  name = "${var.project}-policy"

  policy = data.aws_iam_policy_document.policy.json
}

# Attach the S3 access policy to the IAM role
resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_iam_role_policy_attachment" "policy_attachment_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create an EC2 instance profile and add the IAM role to it
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role" "mail_user_role" {
  name               = "${var.project}-mail-user"
  assume_role_policy = data.aws_iam_policy_document.mail_user_assume.json
}

data "aws_iam_policy_document" "mail_user_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.auth_proxy.arn]
    }
  }
}

data "aws_iam_policy_document" "mail_user_policy" {
  statement {
    sid    = "S3MailAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:List*",
    ]
    resources = [
      "arn:aws:s3:::${var.mail_bucket}",
      "arn:aws:s3:::${var.mail_bucket}/*"
    ]
  }
}

resource "aws_iam_policy" "mail_user_policy" {
  name   = "${var.project}-mail-user"
  policy = data.aws_iam_policy_document.mail_user_policy.json
}

resource "aws_iam_role_policy_attachment" "mail_user_policy" {
  role       = aws_iam_role.mail_user_role.name
  policy_arn = aws_iam_policy.mail_user_policy.arn
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project}-ecs_execution_role"

  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "ecs_execution_policy" {
  name        = "${var.project}-ecs_execution_policy"
  description = "Policy for the ECS execution role"

  policy = data.aws_iam_policy_document.ecs_execution_policy.json
}

data "aws_iam_policy_document" "ecs_execution_policy" {
  statement {
    sid = "DownloadEcrImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.container.arn]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.container.arn}:log-stream:${var.project}/*"]
  }

  statement {
    sid       = "XRay"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_policy_attachment" "ecs_execution_policy" {
  name       = "${var.project}-ecs_execution_policy"
  roles      = [aws_iam_role.ecs_execution_role.name]
  policy_arn = aws_iam_policy.ecs_execution_policy.arn
}
