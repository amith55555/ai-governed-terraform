mock_provider "aws" {
  # The mock otherwise returns a random string for .json, which IAM resources reject.
  # The statements asserted below come from config, not from this value.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # The Lambda function validates that its role is an ARN.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111111111111:role/aigt-test-api-role"
    }
  }
}
mock_provider "archive" {}

variables {
  name        = "aigt-test-api"
  source_dir  = "../../../app"
  table_name  = "aigt-test-items"
  table_arn   = "arn:aws:dynamodb:eu-central-1:111111111111:table/aigt-test-items"
  bucket_name = "aigt-test-items"
  bucket_arn  = "arn:aws:s3:::aigt-test-items"
}

run "role_can_read_item_files" {
  # Mock apply: no AWS calls, but every value is known so the statements can be checked.
  command = apply

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.permissions.statement :
      s.sid == "ItemFileReads"
      && toset(s.actions) == toset(["s3:GetObject"])
      && toset(s.resources) == toset(["arn:aws:s3:::aigt-test-items/items/*"])
    ])
    error_message = "The role must allow exactly s3:GetObject on <bucket>/items/* (needed to sign item file URLs)."
  }

  assert {
    condition = alltrue(flatten([
      for s in data.aws_iam_policy_document.permissions.statement :
      [for a in s.actions : a != "*" && !endswith(a, ":*")]
    ]))
    error_message = "The role policy must not use wildcard actions."
  }

  assert {
    condition = !anytrue([
      for s in data.aws_iam_policy_document.permissions.statement :
      contains(s.resources, "arn:aws:s3:::aigt-test-items/*")
      || contains(s.resources, "arn:aws:s3:::aigt-test-items")
    ])
    error_message = "S3 access must stay limited to the items/ prefix."
  }
}
