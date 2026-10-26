data "aws_iam_policy_document" "deny_data_reads" {
  statement {
    sid    = "DenyS3ObjectReadsExceptState"
    effect = "Deny"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]
    not_resources = ["${aws_s3_bucket.state.arn}/envs/*"]
  }

  statement {
    sid    = "DenyDynamoDBItemReads"
    effect = "Deny"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:GetRecords",
      "dynamodb:PartiQLSelect"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyLogContentReads"
    effect = "Deny"
    actions = [
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
      "logs:StartQuery",
      "logs:GetQueryResults",
      "logs:StartLiveTail"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_deny_data_reads" {
  name        = "aigt-ci-deny-data-reads"
  description = "CI roles: deny reading data (S3 object contents except environment state (envs/*), DynamoDB items, log contents). Resource settings stay readable."
  policy      = data.aws_iam_policy_document.deny_data_reads.json
}

locals {
  readonly_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
