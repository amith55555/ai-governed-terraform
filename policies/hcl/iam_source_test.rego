# Tests for policies/hcl/iam_source.rego
package hcl.iam_source_test

import data.hcl.iam_source

# A file with one policy document, as conftest's HCL parser produces it.
one_doc(statements) := {"data": {"aws_iam_policy_document": {"x": [{"statement": statements}]}}}

one_resource(attrs) := {"resource": {"aws_iam_role_policy": {"x": [attrs]}}}

# PASS: the Lambda permissions in modules/lambda_function (exact actions, exact ARNs)
test_lambda_permissions_pass if {
	f := one_doc([
		{"sid": "WriteOwnLogs", "actions": ["logs:CreateLogStream", "logs:PutLogEvents"], "resources": ["${aws_cloudwatch_log_group.this.arn}:*"]},
		{"sid": "ItemsTable", "actions": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan"], "resources": ["${var.table_arn}"]},
		{"sid": "ItemCopies", "actions": ["s3:PutObject"], "resources": ["${var.bucket_arn}/items/*"]},
	])
	count(iam_source.deny) == 0 with input as f
}

# PASS: the Lambda trust policy (a service principal)
test_service_trust_policy_passes if {
	f := one_doc([{"actions": ["sts:AssumeRole"], "principals": [{"type": "Service", "identifiers": ["lambda.amazonaws.com"]}]}])
	count(iam_source.deny) == 0 with input as f
}

# PASS: the TLS-only bucket policy in modules/s3_bucket: s3:* and principal * in a Deny
test_tls_only_deny_passes if {
	f := one_doc([{
		"sid": "DenyInsecureTransport", "effect": "Deny", "actions": ["s3:*"],
		"resources": ["${aws_s3_bucket.this.arn}", "${aws_s3_bucket.this.arn}/*"],
		"principals": [{"type": "*", "identifiers": ["*"]}],
		"condition": [{"test": "Bool", "variable": "aws:SecureTransport", "values": ["false"]}],
	}])
	count(iam_source.deny) == 0 with input as f
}

# PASS: a policy attribute that points to a policy document
test_policy_from_document_passes if {
	f := {"resource": {
		"aws_iam_role_policy": {"this": [{"policy": "${data.aws_iam_policy_document.permissions.json}"}]},
		"aws_iam_role": {"this": [{"assume_role_policy": "${data.aws_iam_policy_document.assume_role.json}"}]},
	}}
	count(iam_source.deny) == 0 with input as f
}

# PASS: jsonencode in an attribute that is not a policy (the API access log format)
test_jsonencode_outside_policy_passes if {
	f := {"resource": {"aws_apigatewayv2_stage": {"this": [{"access_log_settings": [{"format": "${jsonencode({requestId = \"$context.requestId\"})}"}]}]}}}
	count(iam_source.deny) == 0 with input as f
}

# FAIL (S1): the v2 self-test gap (agent-log 26): sqs:* on a queue created in the same PR
test_sqs_wildcard_on_new_queue_fails if {
	f := one_doc([{"actions": ["sqs:*"], "resources": ["${aws_sqs_queue.this.arn}"]}])
	iam_source.deny == {`data.aws_iam_policy_document.x: Allow with wildcard action "sqs:*" (list the exact actions)`} with input as f
}

# FAIL (S1): a partial wildcard, any service
test_partial_wildcard_fails if {
	f := one_doc([{"actions": ["s3:Get*"], "resources": ["${var.bucket_arn}/*"]}])
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S1): an explicit Allow with "*"
test_explicit_allow_star_fails if {
	f := one_doc([{"effect": "Allow", "actions": ["*"], "resources": ["${var.table_arn}"]}])
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S1): a computed effect counts as Allow (an attacker cannot hide the effect)
test_computed_effect_counts_as_allow if {
	f := one_doc([{"effect": "${var.effect}", "actions": ["dynamodb:*"], "resources": ["${var.table_arn}"]}])
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S1): one bad statement among good ones
test_wildcard_in_second_statement_fails if {
	f := one_doc([
		{"actions": ["s3:PutObject"], "resources": ["${var.bucket_arn}/items/*"]},
		{"actions": ["dynamodb:*"], "resources": ["${var.table_arn}"]},
	])
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S2): every resource
test_resource_star_fails if {
	f := one_doc([{"actions": ["s3:GetObject"], "resources": ["*"]}])
	iam_source.deny == {`data.aws_iam_policy_document.x: Allow on resources "*" (name the exact ARNs)`} with input as f
}

# FAIL (S3): not_actions in an Allow
test_not_actions_fails if {
	f := one_doc([{"not_actions": ["iam:*"], "resources": ["${var.table_arn}"]}])
	iam_source.deny == {`data.aws_iam_policy_document.x: not_actions in an Allow statement is not allowed`} with input as f
}

# FAIL (S3): not_resources in an Allow
test_not_resources_fails if {
	f := one_doc([{"actions": ["s3:GetObject"], "not_resources": ["${var.bucket_arn}/private/*"]}])
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S4): principal type "*" in an Allow (a public bucket policy)
test_public_principal_type_fails if {
	f := one_doc([{"actions": ["s3:GetObject"], "resources": ["${aws_s3_bucket.this.arn}/*"], "principals": [{"type": "*", "identifiers": ["*"]}]}])
	count(iam_source.deny) == 2 with input as f
}

# FAIL (S4): AWS principal "*" (anyone with an AWS account)
test_aws_principal_star_fails if {
	f := one_doc([{"actions": ["sts:AssumeRole"], "principals": [{"type": "AWS", "identifiers": ["*"]}]}])
	iam_source.deny == {`data.aws_iam_policy_document.x: Allow to a principal identifier with "*" is not allowed`} with input as f
}

# FAIL (S5): actions from a variable cannot be read
test_actions_from_variable_fail if {
	f := one_doc([{"actions": "${var.actions}", "resources": ["${var.table_arn}"]}])
	iam_source.deny == {`data.aws_iam_policy_document.x: actions must be a list of plain strings (no variables)`} with input as f
}

# FAIL (S5): one action from a variable inside the list
test_action_interpolated_fails if {
	f := one_doc([{"actions": ["${var.service}:GetObject"], "resources": ["${var.bucket_arn}/*"]}])
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S5): principal identifiers from a variable
test_principal_from_variable_fails if {
	f := one_doc([{"actions": ["sts:AssumeRole"], "principals": [{"type": "AWS", "identifiers": "${var.who}"}]}])
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S6): statements built by a loop
test_dynamic_statement_fails if {
	f := {"data": {"aws_iam_policy_document": {"x": [{"dynamic": {"statement": [{"for_each": "${var.grants}", "content": [{"actions": ["${statement.value}"]}]}]}}]}}}
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S6): JSON merged in from elsewhere
test_source_policy_documents_fail if {
	f := {"data": {"aws_iam_policy_document": {"x": [{"source_policy_documents": ["${var.extra_json}"]}]}}}
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S7): raw JSON with jsonencode
test_jsonencode_policy_fails if {
	f := one_resource({"policy": "${jsonencode({Statement = [{Effect = \"Allow\", Action = \"sqs:*\", Resource = aws_sqs_queue.this.arn}]})}"})
	iam_source.deny == {`resource aws_iam_role_policy.x: policy must be data.aws_iam_policy_document.<name>.json`} with input as f
}

# FAIL (S7): raw JSON in a heredoc
test_heredoc_policy_fails if {
	f := one_resource({"policy": "{\"Statement\": [{\"Effect\": \"Allow\", \"Action\": \"s3:*\", \"Resource\": \"*\"}]}\n"})
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S7): a policy passed in through a variable
test_policy_from_variable_fails if {
	f := one_resource({"policy": "${var.policy_json}"})
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S7): a trust policy written as raw JSON
test_raw_trust_policy_fails if {
	f := {"resource": {"aws_iam_role": {"x": [{"assume_role_policy": "${jsonencode({})}"}]}}}
	count(iam_source.deny) == 1 with input as f
}

# FAIL (S7): an inline policy block inside a role
test_inline_policy_fails if {
	f := {"resource": {"aws_iam_role": {"x": [{
		"assume_role_policy": "${data.aws_iam_policy_document.assume_role.json}",
		"inline_policy": [{"name": "extra", "policy": "${jsonencode({})}"}],
	}]}}}
	count(iam_source.deny) == 1 with input as f
}
