# Shared helpers for the Terraform plan policies.
package terraform.lib

# All resources of one type that will exist after apply.
resources(type) := [rc |
	some rc in input.resource_changes
	rc.mode == "managed"
	rc.type == type
	rc.change.actions != ["delete"]
]

same_module(a, b) if {
	object.get(a, "module_address", "") == object.get(b, "module_address", "")
}

# True if `child` (a resource with a "bucket" argument) belongs to `bucket`.
# New bucket: the child's "bucket" value is unknown at plan time, so the module match is enough.
attached_to(child, bucket) if {
	same_module(child, bucket)
	not child.change.after.bucket
}

attached_to(child, bucket) if {
	same_module(child, bucket)
	child.change.after.bucket == bucket.change.after.bucket
}

# Turn a single value into a one-item list; leave lists alone.
as_list(x) := x if is_array(x)

as_list(x) := [x] if not is_array(x)
