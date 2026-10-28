# Tests for policies/terraform/tags.rego
package terraform.tags_test

import data.terraform.tags

all_tags := {"Project": "p", "Environment": "dev", "ManagedBy": "terraform"}

resource(address, actions, after) := {
	"address": address,
	"mode": "managed",
	"type": "aws_s3_bucket",
	"change": {"actions": actions, "after": after},
}

# PASS: all three tags present
test_all_tags_present_passes if {
	r := resource("aws_s3_bucket.a", ["create"], {"tags_all": all_tags})
	count(tags.deny) == 0 with input as {"resource_changes": [r]}
}

# FAIL: one tag missing
test_missing_environment_fails if {
	r := resource("aws_s3_bucket.b", ["create"], {"tags_all": {"Project": "p", "ManagedBy": "terraform"}})
	tags.deny == {`aws_s3_bucket.b: missing required tag "Environment"`} with input as {"resource_changes": [r]}
}

# FAIL: tag present but empty
test_empty_project_fails if {
	r := resource("aws_s3_bucket.c", ["update"], {"tags_all": object.union(all_tags, {"Project": ""})})
	tags.deny == {`aws_s3_bucket.c: missing required tag "Project"`} with input as {"resource_changes": [r]}
}

# FAIL: no tags at all gives one message per missing tag
test_null_tags_fails_three_times if {
	r := resource("aws_s3_bucket.d", ["create"], {"tags_all": null})
	count(tags.deny) == 3 with input as {"resource_changes": [r]}
}

# PASS: a resource being deleted is ignored
test_deleted_resource_ignored if {
	r := resource("aws_s3_bucket.e", ["delete"], null)
	count(tags.deny) == 0 with input as {"resource_changes": [r]}
}

# PASS: a resource type without tags (no tags_all field) is ignored
test_untaggable_resource_ignored if {
	r := resource("aws_lambda_permission.f", ["create"], {"action": "lambda:InvokeFunction"})
	count(tags.deny) == 0 with input as {"resource_changes": [r]}
}
