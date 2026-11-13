# Policy: IAM least privilege in Terraform source.
# The plan policy (terraform/iam_wildcards.rego) cannot see an IAM policy that
# refers to a resource created in the same plan: its JSON is "known after apply"
# (agent-log entry 26). The source always shows the text, so this policy checks it.
# Input: one .tf file parsed by conftest --parser hcl2.
# Runs on terraform/envs and terraform/modules, not on terraform/bootstrap
# (see scripts/source-policy.sh).
package hcl.iam_source

policy_docs := object.get(object.get(input, "data", {}), "aws_iam_policy_document", {})

as_list(x) := x if is_array(x)

as_list(x) := [] if not is_array(x)

# Every statement block of every aws_iam_policy_document
statements contains {"doc": name, "stmt": s} if {
	some name, blocks in policy_docs
	some doc in blocks
	some s in as_list(object.get(doc, "statement", []))
}

# A statement is an Allow unless it literally says Deny
# (a missing effect means Allow; a computed effect is treated as Allow).
allow_statements contains st if {
	some st in statements
	object.get(st.stmt, "effect", "Allow") != "Deny"
}

literal_list(x) if {
	is_array(x)
	every v in x {
		is_string(v)
		not contains(v, "${")
	}
}

# S1: Allow with a wildcard action, for any service (s3:*, sqs:*, s3:Get*, *)
deny contains msg if {
	some st in allow_statements
	some a in as_list(object.get(st.stmt, "actions", []))
	is_string(a)
	contains(a, "*")
	msg := sprintf("data.aws_iam_policy_document.%s: Allow with wildcard action %q (list the exact actions)", [st.doc, a])
}

# S2: Allow on every resource
deny contains msg if {
	some st in allow_statements
	some r in as_list(object.get(st.stmt, "resources", []))
	r == "*"
	msg := sprintf("data.aws_iam_policy_document.%s: Allow on resources \"*\" (name the exact ARNs)", [st.doc])
}

# S3: NotAction / NotResource / NotPrincipal in an Allow grant everything not listed
deny contains msg if {
	some st in allow_statements
	some key in ["not_actions", "not_resources", "not_principals"]
	object.get(st.stmt, key, null) != null
	msg := sprintf("data.aws_iam_policy_document.%s: %s in an Allow statement is not allowed", [st.doc, key])
}

# S4: Allow to a public principal (type "*", or an identifier with *)
deny contains msg if {
	some st in allow_statements
	some p in as_list(object.get(st.stmt, "principals", []))
	object.get(p, "type", "") == "*"
	msg := sprintf("data.aws_iam_policy_document.%s: Allow to principal type \"*\" (anyone) is not allowed", [st.doc])
}

deny contains msg if {
	some st in allow_statements
	some p in as_list(object.get(st.stmt, "principals", []))
	some i in as_list(object.get(p, "identifiers", []))
	is_string(i)
	contains(i, "*")
	msg := sprintf("data.aws_iam_policy_document.%s: Allow to a principal identifier with \"*\" is not allowed", [st.doc])
}

# S5: actions must be written out (no variables), so this policy can read them
deny contains msg if {
	some st in statements
	not literal_list(object.get(st.stmt, "actions", []))
	msg := sprintf("data.aws_iam_policy_document.%s: actions must be a list of plain strings (no variables)", [st.doc])
}

# S5: principal identifiers in an Allow must be written out too
deny contains msg if {
	some st in allow_statements
	some p in as_list(object.get(st.stmt, "principals", []))
	not literal_list(object.get(p, "identifiers", []))
	msg := sprintf("data.aws_iam_policy_document.%s: principal identifiers must be a list of plain strings (no variables)", [st.doc])
}

# S6: no statements built by loops, and no JSON merged in from elsewhere
deny contains msg if {
	some name, blocks in policy_docs
	some doc in blocks
	object.get(doc, "dynamic", null) != null
	msg := sprintf("data.aws_iam_policy_document.%s: dynamic blocks are not allowed (write each statement out)", [name])
}

merged_json_keys := {"source_json", "override_json", "source_policy_documents", "override_policy_documents"}

deny contains msg if {
	some name, blocks in policy_docs
	some doc in blocks
	some key in merged_json_keys
	object.get(doc, key, null) != null
	msg := sprintf("data.aws_iam_policy_document.%s: %s is not allowed (it merges JSON this policy cannot read)", [name, key])
}

# S7: every policy attribute must come from an aws_iam_policy_document,
# never raw JSON (jsonencode, a heredoc or a variable), which this policy cannot read.
policy_attributes := {"policy", "assume_role_policy"}

deny contains msg if {
	walk(object.get(input, "resource", {}), [path, value])
	count(path) > 2
	path[count(path) - 1] in policy_attributes
	not regex.match(`^\$\{data\.aws_iam_policy_document\.[A-Za-z0-9_-]+\.json\}$`, sprintf("%v", [value]))
	msg := sprintf("resource %s.%s: %s must be data.aws_iam_policy_document.<name>.json", [path[0], path[1], path[count(path) - 1]])
}
