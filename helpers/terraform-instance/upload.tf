locals {
  code_path_prefix = "code"
  go_arch = {
    "x86-64" = "amd64",
    "arm64"  = "arm64",
  }
}

# Compile the program using `make`
resource "null_resource" "program" {
  provisioner "local-exec" {
    command = "make -C ../.. out/pop3-server-${local.go_arch[var.architecture]}"
  }
}

# Upload the compiled binary to an S3 bucket
resource "aws_s3_object" "program" {
  bucket      = aws_s3_bucket.my_bucket.id
  key         = "/${local.code_path_prefix}/pop3-server"
  source      = "${path.module}/../../out/pop3-server-${local.go_arch[var.architecture]}"
  source_hash = "${path.module}/../../out/pop3-server-${local.go_arch[var.architecture]}"

  depends_on = [null_resource.program]
}

resource "aws_s3_object" "systemd_unit" {
  bucket      = aws_s3_bucket.my_bucket.id
  key         = "/${local.code_path_prefix}/pop3-server.service"
  source      = "${path.module}/pop3-server.service"
  source_hash = filemd5("${path.module}/pop3-server.service")
}

resource "aws_s3_object" "auth_proxy" {
  bucket      = aws_s3_bucket.my_bucket.id
  key         = "/${local.code_path_prefix}/auth_proxy.py"
  source      = "${path.module}/auth_proxy.py"
  source_hash = filemd5("${path.module}/auth_proxy.py")
}

resource "aws_s3_object" "systemd_unit_proxy" {
  bucket      = aws_s3_bucket.my_bucket.id
  key         = "/${local.code_path_prefix}/auth-proxy.service"
  source      = "${path.module}/auth-proxy.service"
  source_hash = filemd5("${path.module}/auth-proxy.service")
}

resource "aws_s3_object" "config" {
  bucket      = aws_s3_bucket.my_bucket.id
  key         = "/${local.code_path_prefix}/pop3-server-config.yaml"
  source      = "${path.module}/pop3-server-config.yaml"
  source_hash = filemd5("${path.module}/pop3-server-config.yaml")
}

resource "null_resource" "upload_lock" {
  depends_on = [
    aws_s3_object.program,
    aws_s3_object.systemd_unit,
    aws_s3_object.auth_proxy,
    aws_s3_object.systemd_unit_proxy,
    aws_s3_object.config,
  ]
}
