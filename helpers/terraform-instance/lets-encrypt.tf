locals {
  tls_rotate_function_name = "${var.project}-tls_rotate"
  tls_le_manage_function_name = "${var.project}-letsencrypt-account-manage"
}

resource "aws_iam_role" "tls_rotate" {
  name = local.tls_rotate_function_name

  assume_role_policy = data.aws_iam_policy_document.tls_rotate_assume.json
}

resource "aws_iam_role" "tls_le_rotate" {
  name = local.tls_le_manage_function_name

  assume_role_policy = data.aws_iam_policy_document.tls_rotate_assume.json
}

data "aws_iam_policy_document" "tls_rotate_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "tls_rotate" {
  name        = local.tls_rotate_function_name
  description = "Policy for the tls_rotate Lambda function"

  policy = data.aws_iam_policy_document.tls_rotate.json
}

resource "aws_iam_policy" "tls_le_rotate" {
  name        = local.tls_le_manage_function_name
  description = "Policy for the tls_rotate Lambda function"

  policy = data.aws_iam_policy_document.tls_le_rotate.json
}

data "aws_iam_policy_document" "tls_rotate" {
  statement {
    sid     = "Logging"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    effect  = "Allow"
    resources = [join(":", [
      "arn",
      data.aws_partition.current.id,
      "logs",
      data.aws_region.current.name,
      data.aws_caller_identity.current.account_id,
      "log-group",
      "/aws/lambda/${local.tls_rotate_function_name}",
      "*",
    ])]
  }

  statement {
    sid = "Secrets"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage"
    ]
    resources = [aws_secretsmanager_secret.lets_encrypt.arn]
  }
}

data "aws_iam_policy_document" "tls_le_rotate" {
  statement {
    sid     = "Logging"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    effect  = "Allow"
    resources = [join(":", [
      "arn",
      data.aws_partition.current.id,
      "logs",
      data.aws_region.current.name,
      data.aws_caller_identity.current.account_id,
      "log-group",
      "/aws/lambda/${local.tls_le_manage_function_name}",
      "*",
    ])]
  }

  statement {
    sid = "Secrets"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage"
    ]
    resources = [aws_secretsmanager_secret.lets_encrypt_account.arn]
  }
}

resource "aws_iam_policy_attachment" "tls_rotate" {
  name       = local.tls_rotate_function_name
  roles      = [aws_iam_role.tls_rotate.name]
  policy_arn = aws_iam_policy.tls_rotate.arn
}

resource "aws_iam_policy_attachment" "tls_le_rotate" {
  name       = local.tls_le_manage_function_name
  roles      = [aws_iam_role.tls_le_rotate.name]
  policy_arn = aws_iam_policy.tls_le_rotate.arn
}

resource "aws_lambda_function" "tls_rotate" {
  filename      = data.archive_file.tls_rotate.output_path
  function_name = local.tls_rotate_function_name
  role          = aws_iam_role.tls_rotate.arn
  handler       = "tls_rotate.lambda_handler"
  runtime       = "python3.9"
  architectures = [var.tls_lambda_architecture]
  layers        = [aws_lambda_layer_version.tls_key_layer.arn]
  timeout       = var.tls_rotate_timeout

  source_code_hash = data.archive_file.tls_rotate.output_base64sha256

  environment {
    variables = {
      ACME_EMAIL = var.acme_email
    }
  }

  depends_on = [aws_cloudwatch_log_group.tls_rotate]
}

resource "aws_lambda_function" "tls_le_rotate" {
  filename      = data.archive_file.tls_le_rotate.output_path
  function_name = local.tls_le_manage_function_name
  role          = aws_iam_role.tls_le_rotate.arn
  handler       = "tls_le_rotate.lambda_handler"
  runtime       = "python3.9"
  architectures = [var.tls_lambda_architecture]
  layers        = [aws_lambda_layer_version.tls_key_layer.arn]
  timeout       = var.tls_rotate_timeout

  source_code_hash = data.archive_file.tls_le_rotate.output_base64sha256

  environment {
    variables = {
      TODO = "TODO"
    }
  }

  depends_on = [aws_cloudwatch_log_group.tls_le_rotate]
}

data "archive_file" "tls_rotate" {
  type        = "zip"
  source_file = "tls_rotate.py"
  output_path = "tls_rotate.zip"
}

data "archive_file" "tls_le_rotate" {
  type        = "zip"
  source_file = "tls_le_rotate.py"
  output_path = "tls_le_rotate.zip"
}

resource "aws_cloudwatch_log_group" "tls_rotate" {
  name              = "/aws/lambda/${local.tls_rotate_function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "tls_le_rotate" {
  name              = "/aws/lambda/${local.tls_le_manage_function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_permission" "tls_rotate" {
  statement_id  = "AllowSecretsManagerRotation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tls_rotate.function_name
  principal     = "secretsmanager.${data.aws_partition.current.dns_suffix}"
  source_arn    = aws_secretsmanager_secret.lets_encrypt.arn
}

resource "aws_lambda_permission" "tls_le_rotate" {
  statement_id  = "AllowSecretsManagerRotation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tls_le_rotate.function_name
  principal     = "secretsmanager.${data.aws_partition.current.dns_suffix}"
  source_arn    = aws_secretsmanager_secret.lets_encrypt_account.arn
}

resource "aws_lambda_layer_version" "tls_key_layer" {
  layer_name               = "${var.project}-rsa"
  filename                 = data.archive_file.tls_key_layer.output_path
  description              = "RSA library for Python"
  compatible_runtimes      = ["python3.9"]
  compatible_architectures = ["x86_64", "arm64"]
  license_info             = "Apache-2.0"
  source_code_hash         = data.archive_file.tls_key_layer.output_base64sha256
  depends_on               = [data.archive_file.tls_key_layer]
}

data "archive_file" "tls_key_layer" {
  type        = "zip"
  source_dir  = "${path.module}/tls-key-layer"
  output_path = "tls-key-layer.zip"
  depends_on  = [null_resource.tls_key_layer]
}

locals {
  arch_mapping = {
    "x86_64" = "amd64",
    "arm64" = "arm64",
  }
}

resource "null_resource" "tls_key_layer" {
  # Use `terraform taint null_resource.tls_key_layer` to re-generate
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOF
            set -eu
            mkdir -p tls-key-layer/python
            #curl https://sh.rustup.rs -sSf | sh -s -- -y
            #apt-get install build-essential libssl-dev libffi-dev python3-dev cargo pkg-config
            #python3 -m pip install --platform ${local.arch_mapping[var.tls_lambda_architecture]} --only-binary=:all: -r tls-key-layer-requirements.txt -t tls-key-layer/python
            #python3 -m pip install --only-binary=:all: -r tls-key-layer-requirements.txt -t tls-key-layer/python
            #python3 -m pip install --platform ${var.tls_lambda_architecture} cryptography --no-deps --only-binary=:all: -t tls-key-layer/python
            #python3 -m pip install --platform manylinux2010_arm64 --implementation cp --python 3.9 --upgrade -t tls-key-layer/python -r tls-key-layer-requirements.txt
            docker run --rm -i --platform=linux/${local.arch_mapping[var.tls_lambda_architecture]} -v ${var.external_code_dir}:/code --entrypoint=/code/helpers/terraform-instance/tls-key-layer/pip-install.sh ${var.tls_build_container}
        EOF
  }
}

resource "aws_secretsmanager_secret" "lets_encrypt" {
  name        = "${var.project}-keypair"
  description = "Keypair for ${var.project}"
}

resource "aws_secretsmanager_secret" "lets_encrypt_account" {
  name        = "${var.project}-letsencrypt-account-keypair"
  description = "Letsencrypt account keypair for ${var.project}"
}

resource "aws_secretsmanager_secret_rotation" "lets_encrypt" {
  secret_id           = aws_secretsmanager_secret.lets_encrypt.id
  rotation_lambda_arn = aws_lambda_function.tls_rotate.arn
  rotation_rules {
    automatically_after_days = var.tls_key_rotation_days
  }
}

resource "aws_secretsmanager_secret_rotation" "lets_encrypt_account" {
  secret_id           = aws_secretsmanager_secret.lets_encrypt_account.id
  rotation_lambda_arn = aws_lambda_function.tls_le_rotate.arn
  rotation_rules {
    automatically_after_days = var.tls_key_rotation_days
  }
}
