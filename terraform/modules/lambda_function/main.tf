data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.root}/build/${var.name}.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid = "WriteOwnLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid = "ItemsTable"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Scan"
    ]
    resources = [var.table_arn]
  }

  statement {
    sid = "ItemCopies"
    actions = [
      "s3:PutObject",
    ]
    resources = ["${var.bucket_arn}/items/*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-permissions"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

resource "aws_lambda_function" "this" {
  function_name    = var.name
  role             = aws_iam_role.this.arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.this.output_path
  architectures    = ["arm64"]
  source_code_hash = data.archive_file.this.output_base64sha256
  memory_size      = var.memory_size
  timeout          = 10
  environment {
    variables = {
      TABLE_NAME  = var.table_name
      BUCKET_NAME = var.bucket_name
    }
  }
  depends_on = [
    aws_iam_role_policy.this,
    aws_cloudwatch_log_group.this
  ]
}
