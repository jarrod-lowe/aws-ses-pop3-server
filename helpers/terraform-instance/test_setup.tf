resource "aws_dynamodb_table_item" "password_item" {
  table_name = aws_dynamodb_table.password_table.name
  hash_key   = aws_dynamodb_table.password_table.hash_key

  # user:password
  item = jsonencode({
    "username" : { "S" : "user" },
    "password" : { "S" : "$6$q7HtmON4uS2LUMSQ$9XOrV5pTk14csdZzZZ.WIm3wUBQPNk9K.kDh8CUKcqeQcx9POTL0FGdRKhl.XRSFmGTQVqmyGUKSRPNhEJ0Fw."},
    "bucket" : { "S" : var.mail_bucket },
    "bucket_dir" : { "S" : "" },
    "role" : { "S" : aws_iam_role.mail_user_role.arn },
  })
}