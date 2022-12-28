resource "aws_dynamodb_table" "password_table" {
  name         = "${var.project}-password_table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "username"
  attribute {
    name = "username"
    type = "S"
  }
}
