mock_provider "aws" {}

variables {
  name_prefix   = "aigt-test"
  function_name = "aigt-test-api"
  api_id        = "abc123"
}

run "duration_alarm_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.namespace == "AWS/Lambda" && aws_cloudwatch_metric_alarm.lambda_duration.metric_name == "Duration"
    error_message = "The duration alarm must watch the AWS/Lambda Duration metric."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.statistic == "Maximum"
    error_message = "The duration alarm must use the Maximum statistic."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.period == 300 && aws_cloudwatch_metric_alarm.lambda_duration.evaluation_periods == 1
    error_message = "The duration alarm must evaluate a single 5-minute period."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.threshold == 8000
    error_message = "The default threshold must be 8000 ms (80% of the 10-second timeout)."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.comparison_operator == "GreaterThanThreshold"
    error_message = "The duration alarm must fire when duration is above the threshold."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.dimensions["FunctionName"] == "aigt-test-api"
    error_message = "The duration alarm must target the given function."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name == "aigt-test-lambda-duration"
    error_message = "The duration alarm must be named <name_prefix>-lambda-duration."
  }
}

run "rejects_non_positive_threshold" {
  command = plan

  variables {
    duration_threshold_ms = 0
  }

  expect_failures = [var.duration_threshold_ms]
}
