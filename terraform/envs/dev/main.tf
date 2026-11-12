locals {
  env           = "dev"
  name_prefix   = "aigt-${local.env}"
  bucket_suffix = "7e106d9d"
}

module "table" {
  source              = "../../modules/dynamodb_table"
  name                = "${local.name_prefix}-items"
  deletion_protection = false
}

module "bucket" {
  source        = "../../modules/s3_bucket"
  name          = "${local.name_prefix}-items-${local.bucket_suffix}"
  force_destroy = true
}

module "queue" {
  source            = "../../modules/sqs_queue"
  name              = "${local.name_prefix}-items"
  max_receive_count = 3
}

module "lambda" {
  source               = "../../modules/lambda_function"
  name                 = "${local.name_prefix}-api"
  source_dir           = "${path.module}/../../../app"
  table_name           = module.table.table_name
  table_arn            = module.table.table_arn
  bucket_name          = module.bucket.bucket_name
  bucket_arn           = module.bucket.bucket_arn
  queue_url            = module.queue.queue_url
  queue_arn            = module.queue.queue_arn
  log_retention_days   = 7
  permissions_boundary = "arn:aws:iam::${var.aws_account_id}:policy/aigt-workload-boundary"
}

module "api" {
  source               = "../../modules/http_api"
  name                 = "${local.name_prefix}-api"
  lambda_function_name = module.lambda.function_name
  lambda_invoke_arn    = module.lambda.invoke_arn
  log_retention_days   = 7
}

module "alarms" {
  source        = "../../modules/alarms"
  name_prefix   = local.name_prefix
  function_name = module.lambda.function_name
  api_id        = module.api.api_id
  dlq_name      = module.queue.dlq_name
  alarm_email   = var.alarm_email
}
