mock_provider "aws" {}

variables {
  name                 = "aigt-test-api"
  lambda_function_name = "aigt-test-api"
  lambda_invoke_arn    = "arn:aws:apigateway:eu-central-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-central-1:111111111111:function:aigt-test-api/invocations"
}

run "routes" {
  # Route keys come from config, so a plan is enough.
  command = plan

  assert {
    condition = alltrue([
      for r in ["GET /health", "POST /items", "GET /items", "GET /items/{id}", "GET /items/{id}/file"] :
      contains(keys(aws_apigatewayv2_route.this), r)
    ])
    error_message = "Every expected route must exist, including GET /items/{id}/file."
  }

  assert {
    condition = toset(keys(aws_apigatewayv2_route.this)) == toset([
      "GET /health", "POST /items", "GET /items", "GET /items/{id}", "GET /items/{id}/file",
    ])
    error_message = "The API must expose exactly the five expected routes, no others."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["GET /items/{id}/file"].route_key == "GET /items/{id}/file"
    error_message = "The item file route must use the route key GET /items/{id}/file."
  }
}
