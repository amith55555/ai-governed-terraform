mock_provider "aws" {
  # The mock fills computed strings with random text, and the bucket policy
  # resource rejects anything that is not JSON. The statement itself is
  # checked through the data source's inputs below.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name = "aigt-test-bucket"
}

# Apply against the mock provider so computed values (ids, ARNs) are known
# and every setting below can be checked. No AWS account is needed.
run "safe_defaults" {
  command = apply

  assert {
    condition     = aws_s3_bucket.this.bucket == var.name
    error_message = "The bucket name must come from var.name."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must be off by default."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.this.versioning_configuration).status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Default encryption must be SSE-S3 (AES256)."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be true."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced (ACLs disabled)."
  }

  assert {
    condition = alltrue([
      for r in [
        aws_s3_bucket_versioning.this,
        aws_s3_bucket_server_side_encryption_configuration.this,
        aws_s3_bucket_public_access_block.this,
        aws_s3_bucket_ownership_controls.this,
        aws_s3_bucket_policy.this,
        aws_s3_bucket_lifecycle_configuration.this,
      ] : r.bucket == aws_s3_bucket.this.id
    ])
    error_message = "Every bucket setting must be attached to this module's bucket."
  }
}

run "bucket_policy_denies_insecure_transport" {
  command = apply

  assert {
    condition     = aws_s3_bucket_policy.this.policy == data.aws_iam_policy_document.tls_only.json
    error_message = "The bucket policy must be the TLS-only policy document."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.tls_only.statement) == 1
    error_message = "The TLS-only policy must have exactly one statement."
  }

  assert {
    condition     = data.aws_iam_policy_document.tls_only.statement[0].effect == "Deny"
    error_message = "The TLS-only statement must Deny."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.tls_only.statement[0].actions) == toset(["s3:*"])
    error_message = "The TLS-only statement must cover all S3 actions."
  }

  assert {
    condition = toset(data.aws_iam_policy_document.tls_only.statement[0].resources) == toset([
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ])
    error_message = "The TLS-only statement must cover the bucket and every object in it."
  }

  assert {
    condition = anytrue([
      for p in data.aws_iam_policy_document.tls_only.statement[0].principals :
      p.type == "*" && toset(p.identifiers) == toset(["*"])
    ])
    error_message = "The TLS-only statement must apply to all principals."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.tls_only.statement[0].condition :
      c.test == "Bool" && c.variable == "aws:SecureTransport" && toset(c.values) == toset(["false"])
    ])
    error_message = "The TLS-only statement must match requests where aws:SecureTransport is false."
  }
}

run "lifecycle_cleans_up_old_versions_and_uploads" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1
    error_message = "There must be exactly one lifecycle rule."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled"
    error_message = "The lifecycle rule must be enabled."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration).noncurrent_days == 30
    error_message = "Noncurrent versions must expire after 30 days."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "Incomplete multipart uploads must be aborted after 7 days."
  }
}

run "outputs_match_bucket" {
  command = apply

  assert {
    condition     = output.bucket_name == aws_s3_bucket.this.id
    error_message = "bucket_name must be the bucket's id."
  }

  assert {
    condition     = output.bucket_arn == aws_s3_bucket.this.arn
    error_message = "bucket_arn must be the bucket's ARN."
  }
}

run "force_destroy_can_be_turned_on_for_dev" {
  command = plan

  variables {
    force_destroy = true
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == true
    error_message = "force_destroy = true must reach the bucket."
  }
}
