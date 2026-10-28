# Policy: S3 data is encrypted at rest and in transit.
# Other services in this stack are always encrypted by AWS and cannot be turned off.
# Input: Terraform plan JSON (terraform show -json).
package terraform.encryption

import data.terraform.lib

allowed_algorithms := {"AES256", "aws:kms", "aws:kms:dsse"}

# E1: every bucket has server-side encryption with an allowed algorithm.
deny contains msg if {
	some bucket in lib.resources("aws_s3_bucket")
	not encrypted_at_rest(bucket)
	msg := sprintf("%s: S3 bucket has no server-side encryption configuration", [bucket.address])
}

encrypted_at_rest(bucket) if {
	some sse in lib.resources("aws_s3_bucket_server_side_encryption_configuration")
	lib.attached_to(sse, bucket)
	some r in sse.change.after.rule
	some d in r.apply_server_side_encryption_by_default
	d.sse_algorithm in allowed_algorithms
}

# E2: every bucket has a policy that denies requests without TLS (HTTPS).
deny contains msg if {
	some bucket in lib.resources("aws_s3_bucket")
	not tls_only(bucket)
	msg := sprintf("%s: S3 bucket has no bucket policy that denies non-TLS requests", [bucket.address])
}

tls_only(bucket) if {
	some pol in lib.resources("aws_s3_bucket_policy")
	lib.attached_to(pol, bucket)
	denies_insecure_transport(pol)
}

# New bucket: the policy text is unknown at plan time, so we can only check it exists.
denies_insecure_transport(pol) if not pol.change.after.policy

denies_insecure_transport(pol) if {
	doc := json.unmarshal(pol.change.after.policy)
	some stmt in lib.as_list(doc.Statement)
	stmt.Effect == "Deny"
	"false" in lib.as_list(stmt.Condition.Bool["aws:SecureTransport"])
}
