mock_provider "aws" {
  override_data {
    target = data.aws_iam_policy_document.permissions
    values = {
      json = "{}"
    }
  }
  override_data {
    target = data.aws_iam_policy_document.assume_role
    values = {
      json = "{}"
    }
  }
}

mock_provider "archive" {}

variables {
  name        = "aigt-test-api"
  source_dir  = "../../../app"
  table_name  = "aigt-test-items"
  table_arn   = "arn:aws:dynamodb:eu-central-1:111111111111:table/aigt-test-items"
  bucket_name = "aigt-test-items-bucket"
  bucket_arn  = "arn:aws:s3:::aigt-test-items-bucket"
}

run "s3_object_access_on_items_bucket" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.permissions.statement :
      s.sid == "ItemsBucketObjects"
      && toset(s.actions) == toset(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"])
      && toset(s.resources) == toset(["arn:aws:s3:::aigt-test-items-bucket/*"])
    ])
    error_message = "The role must get exactly s3:GetObject, s3:PutObject and s3:DeleteObject on the items bucket's objects."
  }

  assert {
    condition = alltrue(flatten([
      for s in data.aws_iam_policy_document.permissions.statement :
      [for a in s.actions : !strcontains(a, "*")]
    ]))
    error_message = "No wildcard actions in the Lambda role policy."
  }
}
