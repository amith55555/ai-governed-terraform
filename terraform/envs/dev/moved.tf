# Module instance renames. These blocks move state to the new addresses,
# so no resource is destroyed or recreated.
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
