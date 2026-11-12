locals {
  env           = "prod"
  name_prefix   = "aigt-${local.env}"
  bucket_suffix = "7e106d9d"
}

module "items_table" {
  source              = "../../modules/dynamodb_table"
  name                = "${local.name_prefix}-items"
  deletion_protection = true
}

module "items_bucket" {
  source        = "../../modules/s3_bucket"
  name          = "${local.name_prefix}-items-${local.bucket_suffix}"
  force_destroy = false
}

module "api_function" {
  source               = "../../modules/lambda_function"
  name                 = "${local.name_prefix}-api"
  source_dir           = "${path.module}/../../../app"
  table_name           = module.items_table.table_name
  table_arn            = module.items_table.table_arn
  bucket_name          = module.items_bucket.bucket_name
  bucket_arn           = module.items_bucket.bucket_arn
  memory_size          = 256
  log_retention_days   = 30
  permissions_boundary = "arn:aws:iam::${var.aws_account_id}:policy/aigt-workload-boundary"
}

module "api" {
  source               = "../../modules/http_api"
  name                 = "${local.name_prefix}-api"
  lambda_function_name = module.api_function.function_name
  lambda_invoke_arn    = module.api_function.invoke_arn
  log_retention_days   = 30
}

module "alarms" {
  source        = "../../modules/alarms"
  name_prefix   = local.name_prefix
  function_name = module.api_function.function_name
  api_id        = module.api.api_id
  alarm_email   = var.alarm_email
}

