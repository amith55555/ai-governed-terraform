mock_provider "aws" {}

variables {
  name_prefix   = "aigt-test"
  function_name = "aigt-test-api"
  api_id        = "abc123"
}

run "duration_alarm_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name == "aigt-test-lambda-duration"
    error_message = "Duration alarm name must be <name_prefix>-lambda-duration."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.namespace == "AWS/Lambda"
    error_message = "Duration alarm namespace must be AWS/Lambda."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.metric_name == "Duration"
    error_message = "Duration alarm must watch the Duration metric."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.dimensions["FunctionName"] == "aigt-test-api"
    error_message = "Duration alarm must be scoped to the function."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.statistic == "Maximum"
    error_message = "Duration alarm statistic must be Maximum."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.period == 300
    error_message = "Duration alarm period must be 300 seconds."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.threshold == 8000
    error_message = "Duration alarm threshold must default to 8000 ms (80% of the 10 s timeout)."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.comparison_operator == "GreaterThanThreshold"
    error_message = "Duration alarm must use GreaterThanThreshold."
  }
}

run "rejects_zero_duration_threshold" {
  command = plan

  variables {
    lambda_duration_threshold_ms = 0
  }

  expect_failures = [var.lambda_duration_threshold_ms]
}
