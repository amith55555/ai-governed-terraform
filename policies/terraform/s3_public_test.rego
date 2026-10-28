# Tests for policies/terraform/s3_public.rego
package terraform.s3_public_test

import data.terraform.s3_public

res(type, address, module, actions, after) := {
	"address": address,
	"module_address": module,
	"mode": "managed",
	"type": type,
	"change": {"actions": actions, "after": after},
}

bucket := res("aws_s3_bucket", "module.b.aws_s3_bucket.this", "module.b", ["create"], {"bucket": "my-bucket"})

full_block := {
	"block_public_acls": true,
	"block_public_policy": true,
	"ignore_public_acls": true,
	"restrict_public_buckets": true,
}

# New bucket: the block's "bucket" value is unknown at plan time, so it is missing.
pab := res("aws_s3_bucket_public_access_block", "module.b.aws_s3_bucket_public_access_block.this", "module.b", ["create"], full_block)

policy(statement) := res("aws_s3_bucket_policy", "module.b.aws_s3_bucket_policy.this", "module.b", ["create"], {"policy": json.marshal({"Version": "2012-10-17", "Statement": [statement]})})

no_block_msg := "module.b.aws_s3_bucket.this: S3 bucket has no public access block with all four settings true"

# PASS: bucket with a full block in the same module
test_bucket_with_full_block_passes if {
	count(s3_public.deny) == 0 with input as {"resource_changes": [bucket, pab]}
}

# FAIL (R1): bucket without a block
test_bucket_without_block_fails if {
	s3_public.deny == {no_block_msg} with input as {"resource_changes": [bucket]}
}

# FAIL (R1): a block in another module does not protect this bucket
test_block_in_other_module_does_not_count if {
	other := res("aws_s3_bucket_public_access_block", "module.x.aws_s3_bucket_public_access_block.this", "module.x", ["create"], full_block)
	s3_public.deny == {no_block_msg} with input as {"resource_changes": [bucket, other]}
}

# FAIL (R2): one setting turned off
test_block_with_false_setting_fails if {
	weak := res("aws_s3_bucket_public_access_block", "module.b.aws_s3_bucket_public_access_block.this", "module.b", ["create"], object.union(full_block, {"block_public_policy": false}))
	"module.b.aws_s3_bucket_public_access_block.this: all four public access settings must be true" in s3_public.deny with input as {"resource_changes": [bucket, weak]}
}

# FAIL (R3): public ACL
test_public_acl_fails if {
	acl := res("aws_s3_bucket_acl", "module.b.aws_s3_bucket_acl.this", "module.b", ["create"], {"acl": "public-read"})
	s3_public.deny == {`module.b.aws_s3_bucket_acl.this: public ACL "public-read" is not allowed`} with input as {"resource_changes": [bucket, pab, acl]}
}

# FAIL (R4): policy allows Principal "*"
test_policy_allow_everyone_fails if {
	p := policy({"Effect": "Allow", "Principal": "*", "Action": "s3:GetObject", "Resource": "*"})
	count(s3_public.deny) == 1 with input as {"resource_changes": [bucket, pab, p]}
}

# FAIL (R4): the same, written as {"AWS": ["*"]}
test_policy_allow_everyone_aws_list_fails if {
	p := policy({"Effect": "Allow", "Principal": {"AWS": ["*"]}, "Action": "s3:GetObject", "Resource": "*"})
	count(s3_public.deny) == 1 with input as {"resource_changes": [bucket, pab, p]}
}

# PASS (R4): a Deny to everyone, like our TLS-only policy, is fine
test_policy_deny_everyone_passes if {
	p := policy({"Effect": "Deny", "Principal": "*", "Action": "s3:*", "Resource": "*", "Condition": {"Bool": {"aws:SecureTransport": "false"}}})
	count(s3_public.deny) == 0 with input as {"resource_changes": [bucket, pab, p]}
}

# PASS: a bucket being deleted is ignored
test_deleted_bucket_ignored if {
	gone := res("aws_s3_bucket", "module.b.aws_s3_bucket.this", "module.b", ["delete"], null)
	count(s3_public.deny) == 0 with input as {"resource_changes": [gone]}
}
