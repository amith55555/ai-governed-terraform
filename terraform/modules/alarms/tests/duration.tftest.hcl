mock_provider "aws" {}

variables {
  name_prefix              = "aigt-test"
  function_name            = "aigt-test-api"
  api_id                   = "abc123"
  function_timeout_seconds = 10
}

run "duration_alarm_at_80_percent_of_timeout" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.threshold == 8000
    error_message = "A 10 s timeout must give an 8000 ms duration threshold."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.statistic == "Maximum" && aws_cloudwatch_metric_alarm.lambda_duration.period == 300
    error_message = "The duration alarm must use the Maximum statistic over 5 minutes."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.comparison_operator == "GreaterThanThreshold"
    error_message = "The duration alarm must fire above the threshold."
  }
}

run "rejects_invalid_timeout" {
  command = plan

  variables {
    function_timeout_seconds = 0
  }

  expect_failures = [var.function_timeout_seconds]
}
