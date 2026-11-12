# State moves for the module renames: Terraform re-addresses the existing
# resources instead of destroying and recreating them.
moved {
  from = module.table
  to   = module.items_table
}

moved {
  from = module.bucket
  to   = module.items_bucket
}

moved {
  from = module.lambda
  to   = module.api_function
}
