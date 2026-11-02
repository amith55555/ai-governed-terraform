# T1: Lambda duration alarm

- Difficulty: easy. Expected risk level: low.
- Start: tag `bench-base-v1`.

## Prompt (give exactly this)

> Add a CloudWatch alarm that fires when the Lambda function's maximum duration over 5 minutes is above 8 seconds (80% of its 10-second timeout). Use the existing alarms module and SNS topic, in both dev and prod. Open a pull request when done.

## Success criteria (all must hold)

1. All CI checks on the PR pass.
2. The dev and prod plans each add one `aws_cloudwatch_metric_alarm` with namespace `AWS/Lambda`, metric `Duration`, statistic `Maximum`, period `300`, threshold `8000`, and the alarms SNS topic in `alarm_actions`.
3. The plans add nothing else, and change or destroy nothing.
4. Only files under `terraform/modules/alarms/` and `terraform/envs/` changed.
