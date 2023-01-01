locals {
  auth_proxy_function_name = "${var.project}-auth-proxy"
}

resource "aws_iam_role" "auth_proxy" {
  name = local.auth_proxy_function_name

  assume_role_policy = data.aws_iam_policy_document.auth_proxy_assume.json
}

data "aws_iam_policy_document" "auth_proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "auth_proxy" {
  name        = local.auth_proxy_function_name
  description = "Policy for the auth-proxy Lambda function"

  policy = data.aws_iam_policy_document.auth_proxy.json
}

data "aws_iam_policy_document" "auth_proxy" {
  statement {
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    effect  = "Allow"
    resources = [join(":", [
      "arn",
      data.aws_partition.current.id,
      "logs",
      data.aws_region.current.name,
      data.aws_caller_identity.current.account_id,
      "log-group",
      "/aws/lambda/${local.auth_proxy_function_name}",
      "*",
    ])]
  }

  statement {
    sid       = "AssumeRole"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.mail_user_role.arn]
  }

  statement {
    sid       = "GetUserConfig"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.password_table.arn]
  }

  statement {
    sid       = "FindBucket"
    actions   = ["s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::*"]
  }
}

resource "aws_iam_policy_attachment" "auth_proxy" {
  name       = local.auth_proxy_function_name
  roles      = [aws_iam_role.auth_proxy.name]
  policy_arn = aws_iam_policy.auth_proxy.arn
}

resource "aws_lambda_function" "auth_proxy" {
  filename      = data.archive_file.auth_proxy.output_path
  function_name = local.auth_proxy_function_name
  role          = aws_iam_role.auth_proxy.arn
  handler       = "auth_proxy.handler"
  runtime       = "python3.9"
  architectures = ["arm64"]

  source_code_hash = data.archive_file.auth_proxy.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.password_table.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.auth_proxy]
}

data "archive_file" "auth_proxy" {
  type        = "zip"
  source_file = "auth_proxy.py"
  output_path = "auth_proxy.zip"
}

resource "aws_cloudwatch_log_group" "auth_proxy" {
  name              = "/aws/lambda/${local.auth_proxy_function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_permission" "auth_proxy" {
  statement_id  = "AllowPop3Server"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_proxy.function_name
  principal     = aws_iam_role.ec2_role.arn
}
