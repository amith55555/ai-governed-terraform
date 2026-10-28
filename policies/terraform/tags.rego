# Policy: every taggable resource must carry the required tags.
# Input: Terraform plan JSON (terraform show -json).
package terraform.tags

required_tags := {"Project", "Environment", "ManagedBy"}

# Resources that will exist after apply and support tags.
taggable contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	rc.change.actions != ["delete"]
	"tags_all" in object.keys(rc.change.after)
}

deny contains msg if {
	some rc in taggable
	some tag in required_tags
	not has_tag(rc.change.after.tags_all, tag)
	msg := sprintf("%s: missing required tag %q", [rc.address, tag])
}

has_tag(tags, name) if {
	is_string(tags[name])
	tags[name] != ""
}
