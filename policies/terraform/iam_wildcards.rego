# Policy: no wildcard or over-broad IAM permissions.
# Input: Terraform plan JSON (terraform show -json).
package terraform.iam_wildcards

import data.terraform.lib

policy_types := {"aws_iam_role_policy", "aws_iam_policy", "aws_iam_user_policy", "aws_iam_group_policy"}

attachment_types := {
	"aws_iam_role_policy_attachment",
	"aws_iam_user_policy_attachment",
	"aws_iam_group_policy_attachment",
	"aws_iam_policy_attachment",
}

# Every policy document whose text is known at plan time.
policy_docs contains {"address": rc.address, "text": rc.change.after.policy} if {
	some t in policy_types
	some rc in lib.resources(t)
	rc.change.after.policy
}

policy_docs contains {"address": rc.address, "text": p.policy} if {
	some rc in lib.resources("aws_iam_role")
	some p in rc.change.after.inline_policy
	p.policy
}

# Every Allow statement in those documents. A missing Effect means Allow.
allow_statements contains {"address": d.address, "stmt": stmt} if {
	some d in policy_docs
	doc := json.unmarshal(d.text)
	some stmt in lib.as_list(doc.Statement)
	object.get(stmt, "Effect", "Allow") == "Allow"
}

# W1: wildcard actions
deny contains msg if {
	some s in allow_statements
	some action in lib.as_list(object.get(s.stmt, "Action", []))
	contains(action, "*")
	msg := sprintf("%s: IAM policy allows wildcard action %q", [s.address, action])
}

# W2: every resource
deny contains msg if {
	some s in allow_statements
	some resource in lib.as_list(object.get(s.stmt, "Resource", []))
	resource == "*"
	msg := sprintf("%s: IAM policy allows Resource \"*\"", [s.address])
}

# W3: NotAction / NotResource in an Allow
deny contains msg if {
	some s in allow_statements
	some key in ["NotAction", "NotResource"]
	s.stmt[key]
	msg := sprintf("%s: IAM policy uses %s in an Allow statement", [s.address, key])
}

# W4: broad AWS managed policies
deny contains msg if {
	some t in attachment_types
	some rc in lib.resources(t)
	broad_managed_policy(rc.change.after.policy_arn)
	msg := sprintf("%s: attaches broad AWS managed policy %q", [rc.address, rc.change.after.policy_arn])
}

broad_managed_policy(arn) if arn in {
	"arn:aws:iam::aws:policy/AdministratorAccess",
	"arn:aws:iam::aws:policy/PowerUserAccess",
}

broad_managed_policy(arn) if {
	startswith(arn, "arn:aws:iam::aws:policy/")
	endswith(arn, "FullAccess")
}

# W5: policy text unknown at plan time -> warn only (Checkov scans the source).
warn contains msg if {
	some t in policy_types
	some rc in lib.resources(t)
	not rc.change.after.policy
	msg := sprintf("%s: IAM policy text unknown at plan time, wildcard check skipped (Checkov scans the source)", [rc.address])
}
