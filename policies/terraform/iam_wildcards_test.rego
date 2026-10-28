# Tests for policies/terraform/iam_wildcards.rego
package terraform.iam_wildcards_test

import data.terraform.iam_wildcards

res(type, address, after) := {
	"address": address,
	"module_address": "module.l",
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after},
}

# Uses AWS's documentation example account ID, not a real one.
table_arn := "arn:aws:dynamodb:eu-central-1:111122223333:table/aigt-dev-items"

role_policy(statements) := res("aws_iam_role_policy", "module.l.aws_iam_role_policy.this", {"policy": json.marshal({"Version": "2012-10-17", "Statement": statements})})

good := {"Effect": "Allow", "Action": ["dynamodb:GetItem", "dynamodb:PutItem"], "Resource": table_arn}

denials_for(statements) := result if {
	result := iam_wildcards.deny with input as {"resource_changes": [role_policy(statements)]}
}

# PASS: exact actions on an exact resource (like the Lambda role)
test_scoped_policy_passes if {
	count(denials_for([good])) == 0
}

# PASS: a scoped path wildcard in Resource is fine
test_path_wildcard_resource_passes if {
	count(denials_for([{"Effect": "Allow", "Action": "s3:PutObject", "Resource": "arn:aws:s3:::my-bucket/items/*"}])) == 0
}

# PASS: a broad Deny is fine (it makes things safer)
test_broad_deny_passes if {
	count(denials_for([good, {"Effect": "Deny", "Action": "*", "Resource": "*"}])) == 0
}

# FAIL (W1): Action "*"
test_action_star_fails if {
	denials_for([{"Effect": "Allow", "Action": "*", "Resource": table_arn}]) == {`module.l.aws_iam_role_policy.this: IAM policy allows wildcard action "*"`}
}

# FAIL (W1): service wildcard, hidden next to a good statement
test_service_wildcard_fails if {
	denials_for([good, {"Effect": "Allow", "Action": ["s3:*"], "Resource": "arn:aws:s3:::my-bucket"}]) == {`module.l.aws_iam_role_policy.this: IAM policy allows wildcard action "s3:*"`}
}

# FAIL (W1): prefix wildcard
test_prefix_wildcard_fails if {
	count(denials_for([{"Effect": "Allow", "Action": "s3:Get*", "Resource": "arn:aws:s3:::my-bucket/*"}])) == 1
}

# FAIL (W2): Resource "*"
test_resource_star_fails if {
	denials_for([{"Effect": "Allow", "Action": "dynamodb:GetItem", "Resource": "*"}]) == {`module.l.aws_iam_role_policy.this: IAM policy allows Resource "*"`}
}

# FAIL: missing Effect counts as Allow
test_missing_effect_counts_as_allow if {
	count(denials_for([{"Action": "*", "Resource": table_arn}])) == 1
}

# FAIL (W3): NotAction in an Allow
test_not_action_fails if {
	denials_for([{"Effect": "Allow", "NotAction": "iam:*", "Resource": table_arn}]) == {"module.l.aws_iam_role_policy.this: IAM policy uses NotAction in an Allow statement"}
}

# FAIL: wildcard inside an aws_iam_role inline_policy block
test_role_inline_policy_fails if {
	role := res("aws_iam_role", "module.l.aws_iam_role.this", {"inline_policy": [{"name": "x", "policy": json.marshal({"Statement": [{"Effect": "Allow", "Action": "*", "Resource": table_arn}]})}]})
	count(iam_wildcards.deny) == 1 with input as {"resource_changes": [role]}
}

# FAIL (W4): attaching AdministratorAccess
test_admin_attachment_fails if {
	att := res("aws_iam_role_policy_attachment", "module.l.aws_iam_role_policy_attachment.admin", {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"})
	iam_wildcards.deny == {`module.l.aws_iam_role_policy_attachment.admin: attaches broad AWS managed policy "arn:aws:iam::aws:policy/AdministratorAccess"`} with input as {"resource_changes": [att]}
}

# WARN (W5): policy text unknown gives a warning, not a failure
test_unknown_policy_warns_only if {
	unknown := res("aws_iam_role_policy", "module.l.aws_iam_role_policy.this", {})
	count(iam_wildcards.deny) == 0 with input as {"resource_changes": [unknown]}
	count(iam_wildcards.warn) == 1 with input as {"resource_changes": [unknown]}
}
