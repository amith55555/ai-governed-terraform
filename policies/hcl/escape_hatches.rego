# Policy: no escape hatches in Terraform source.
# Blocks anything that runs or fetches code outside the reviewed repo.
# Input: one .tf file parsed by conftest --parser hcl2.
package hcl.escape_hatches

allowed_type_prefixes := {"aws_", "archive_"}

allowed_provider_sources := {
	"hashicorp/aws",
	"hashicorp/archive",
	"registry.terraform.io/hashicorp/aws",
	"registry.terraform.io/hashicorp/archive",
}

# H1: no provisioner blocks anywhere
deny contains msg if {
	walk(input, [path, _])
	count(path) > 0
	path[count(path) - 1] == "provisioner"
	msg := "provisioner blocks are not allowed (they run arbitrary commands)"
}

# H2: only aws_* and archive_* resource and data types
deny contains msg if {
	some kind in ["resource", "data"]
	some t, _ in object.get(input, kind, {})
	not allowed_type(t)
	msg := sprintf("%s type %q is not allowed (only aws_* and archive_*)", [kind, t])
}

allowed_type(t) if {
	some prefix in allowed_type_prefixes
	startswith(t, prefix)
}

# H3: module sources must be one of our own modules
deny contains msg if {
	walk(object.get(input, "module", {}), [path, value])
	count(path) > 0
	path[count(path) - 1] == "source"
	not regex.match(`^\.\./\.\./modules/[a-z0-9_]+$`, value)
	msg := sprintf("module source %q is not allowed (must be ../../modules/<name>)", [value])
}

# H4: only the providers we use, from HashiCorp
deny contains msg if {
	walk(object.get(input, "terraform", {}), [path, value])
	"required_providers" in path
	path[count(path) - 1] == "source"
	not value in allowed_provider_sources
	msg := sprintf("provider source %q is not allowed", [value])
}
