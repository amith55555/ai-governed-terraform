data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${var.aws_account_id}:log-group:/aws/lambda/aigt-*:*"
    ]
  }

  statement {
    sid    = "ProjectTablesItems"
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem"
    ]
    resources = [
      "arn:aws:dynamodb:${var.region}:${var.aws_account_id}:table/aigt-*"
    ]
  }

  statement {
    sid    = "ProjectBucketsObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::aigt-dev-*/*",
      "arn:aws:s3:::aigt-prod-*/*"
    ]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "aigt-workload-boundary"
  description = "Boundary policy for workload IAM roles to restrict access to project resources."
  policy      = data.aws_iam_policy_document.workload_boundary.json
}
