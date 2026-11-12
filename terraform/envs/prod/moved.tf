# Renamed module instances. These blocks move existing state to the new
# addresses so nothing is destroyed or recreated.
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
