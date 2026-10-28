# Tests for policies/hcl/escape_hatches.rego
package hcl.escape_hatches_test

import data.hcl.escape_hatches

# A file shaped like our real code, as conftest's HCL parser produces it.
good := {
	"terraform": [{"required_providers": [{"aws": {"source": "hashicorp/aws", "version": "~> 6.0"}}]}],
	"resource": {"aws_s3_bucket": {"this": [{"bucket": "${var.name}"}]}},
	"data": {"aws_iam_policy_document": {"x": [{}]}, "archive_file": {"this": [{}]}},
	"module": {"bucket": [{"source": "../../modules/s3_bucket"}]},
}

# PASS: normal code
test_normal_code_passes if {
	count(escape_hatches.deny) == 0 with input as good
}

# PASS: full registry address of an allowed provider
test_registry_provider_address_passes if {
	f := {"terraform": [{"required_providers": [{"aws": {"source": "registry.terraform.io/hashicorp/aws"}}]}]}
	count(escape_hatches.deny) == 0 with input as f
}

# FAIL (H1): provisioner inside a resource
test_provisioner_fails if {
	f := {"resource": {"aws_s3_bucket": {"x": [{"provisioner": {"local-exec": [{"command": "curl example.com"}]}}]}}}
	escape_hatches.deny == {"provisioner blocks are not allowed (they run arbitrary commands)"} with input as f
}

# FAIL (H2): data "external" runs a program during plan
test_external_data_fails if {
	f := {"data": {"external": {"x": [{"program": ["sh", "-c", "env"]}]}}}
	escape_hatches.deny == {`data type "external" is not allowed (only aws_* and archive_*)`} with input as f
}

# FAIL (H2): data "http" can send data anywhere during plan
test_http_data_fails if {
	f := {"data": {"http": {"x": [{"url": "https://example.com"}]}}}
	count(escape_hatches.deny) == 1 with input as f
}

# FAIL (H2): resource types outside the allowlist
test_null_resource_fails if {
	f := {"resource": {"null_resource": {"x": [{}]}}}
	count(escape_hatches.deny) == 1 with input as f
}

# FAIL (H3): remote module
test_git_module_fails if {
	f := {"module": {"x": [{"source": "git::https://github.com/someone/evil.git"}]}}
	escape_hatches.deny == {`module source "git::https://github.com/someone/evil.git" is not allowed (must be ../../modules/<name>)`} with input as f
}

# FAIL (H3): local path that escapes terraform/modules
test_module_outside_modules_dir_fails if {
	f := {"module": {"x": [{"source": "../../../tests/unscanned"}]}}
	count(escape_hatches.deny) == 1 with input as f
}

# FAIL (H4): look-alike provider
test_fake_provider_fails if {
	f := {"terraform": [{"required_providers": [{"aws": {"source": "someone/aws"}}]}]}
	escape_hatches.deny == {`provider source "someone/aws" is not allowed`} with input as f
}
