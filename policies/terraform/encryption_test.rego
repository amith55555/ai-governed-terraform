# Tests for policies/terraform/encryption.rego
package terraform.encryption_test

import data.terraform.encryption

res(type, address, module, actions, after) := {
	"address": address,
	"module_address": module,
	"mode": "managed",
	"type": type,
	"change": {"actions": actions, "after": after},
}

bucket := res("aws_s3_bucket", "module.b.aws_s3_bucket.this", "module.b", ["create"], {"bucket": "my-bucket"})

sse_in(module) := res("aws_s3_bucket_server_side_encryption_configuration", sprintf("%s.aws_s3_bucket_server_side_encryption_configuration.this", [module]), module, ["create"], {"rule": [{"apply_server_side_encryption_by_default": [{"sse_algorithm": "AES256"}]}]})

tls_statement := {"Effect": "Deny", "Principal": "*", "Action": "s3:*", "Resource": "*", "Condition": {"Bool": {"aws:SecureTransport": "false"}}}

policy_with(statement) := res("aws_s3_bucket_policy", "module.b.aws_s3_bucket_policy.this", "module.b", ["create"], {"policy": json.marshal({"Version": "2012-10-17", "Statement": [statement]})})

# New bucket: policy text unknown at plan time, so "policy" is missing.
policy_unknown := res("aws_s3_bucket_policy", "module.b.aws_s3_bucket_policy.this", "module.b", ["create"], {})

no_sse_msg := "module.b.aws_s3_bucket.this: S3 bucket has no server-side encryption configuration"

no_tls_msg := "module.b.aws_s3_bucket.this: S3 bucket has no bucket policy that denies non-TLS requests"

# PASS: encryption config and a known TLS-only policy
test_encrypted_bucket_passes if {
	count(encryption.deny) == 0 with input as {"resource_changes": [bucket, sse_in("module.b"), policy_with(tls_statement)]}
}

# PASS: new bucket whose policy text is not known yet
test_new_bucket_policy_unknown_passes if {
	count(encryption.deny) == 0 with input as {"resource_changes": [bucket, sse_in("module.b"), policy_unknown]}
}

# FAIL (E1): no encryption config
test_missing_sse_fails if {
	encryption.deny == {no_sse_msg} with input as {"resource_changes": [bucket, policy_with(tls_statement)]}
}

# FAIL (E1): encryption config in another module does not count
test_sse_in_other_module_fails if {
	encryption.deny == {no_sse_msg} with input as {"resource_changes": [bucket, sse_in("module.x"), policy_with(tls_statement)]}
}

# FAIL (E2): no bucket policy at all
test_missing_policy_fails if {
	encryption.deny == {no_tls_msg} with input as {"resource_changes": [bucket, sse_in("module.b")]}
}

# FAIL (E2): a policy without the TLS deny
test_policy_without_tls_deny_fails if {
	other := {"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::111122223333:role/reader"}, "Action": "s3:GetObject", "Resource": "*"}
	encryption.deny == {no_tls_msg} with input as {"resource_changes": [bucket, sse_in("module.b"), policy_with(other)]}
}

# PASS: a bucket being deleted is ignored
test_deleted_bucket_ignored if {
	gone := res("aws_s3_bucket", "module.b.aws_s3_bucket.this", "module.b", ["delete"], null)
	count(encryption.deny) == 0 with input as {"resource_changes": [gone]}
}
