# Policy: no S3 bucket may be public.
# Input: Terraform plan JSON (terraform show -json).
package terraform.s3_public

import data.terraform.lib

# R1: every bucket needs a public access block with all four settings true.
deny contains msg if {
	some bucket in lib.resources("aws_s3_bucket")
	not has_full_block(bucket)
	msg := sprintf("%s: S3 bucket has no public access block with all four settings true", [bucket.address])
}

has_full_block(bucket) if {
	some pab in lib.resources("aws_s3_bucket_public_access_block")
	lib.attached_to(pab, bucket)
	all_blocked(pab)
}

all_blocked(pab) if {
	pab.change.after.block_public_acls == true
	pab.change.after.block_public_policy == true
	pab.change.after.ignore_public_acls == true
	pab.change.after.restrict_public_buckets == true
}

# R2: no public access block may have a setting turned off.
deny contains msg if {
	some pab in lib.resources("aws_s3_bucket_public_access_block")
	not all_blocked(pab)
	msg := sprintf("%s: all four public access settings must be true", [pab.address])
}

# R3: no public ACL.
public_acls := {"public-read", "public-read-write", "authenticated-read"}

deny contains msg if {
	some acl in lib.resources("aws_s3_bucket_acl")
	acl.change.after.acl in public_acls
	msg := sprintf("%s: public ACL %q is not allowed", [acl.address, acl.change.after.acl])
}

# R4: no bucket policy that allows everyone.
deny contains msg if {
	some pol in lib.resources("aws_s3_bucket_policy")
	doc := json.unmarshal(pol.change.after.policy)
	some stmt in lib.as_list(doc.Statement)
	stmt.Effect == "Allow"
	everyone(stmt.Principal)
	msg := sprintf("%s: bucket policy allows access to everyone (Principal \"*\")", [pol.address])
}

everyone(p) if p == "*"

everyone(p) if p.AWS == "*"

everyone(p) if {
	is_array(p.AWS)
	"*" in p.AWS
}
