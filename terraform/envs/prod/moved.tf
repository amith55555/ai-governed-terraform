# Module instances were renamed. These blocks move the existing state to the
# new addresses, so Terraform does not destroy and recreate anything.
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
