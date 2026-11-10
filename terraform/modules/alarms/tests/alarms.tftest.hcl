mock_provider "aws" {}

variables {
  name_prefix   = "aigt-test"
  function_name = "aigt-test-api"
  api_id        = "abc123"
}

run "lambda_errors_evaluation_periods" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_errors.evaluation_periods == 2
    error_message = "The Lambda errors alarm must evaluate over 2 periods."
  }
}
