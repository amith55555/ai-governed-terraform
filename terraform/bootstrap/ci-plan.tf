data "aws_iam_policy_document" "ci_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:pull_request"]
    }
  }
}

resource "aws_iam_role" "ci_plan" {
  name                 = "aigt-ci-plan"
  assume_role_policy   = data.aws_iam_policy_document.ci_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "ci_plan_readonly" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = local.readonly_policy_arn
}

resource "aws_iam_role_policy_attachment" "ci_plan_deny_data" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = aws_iam_policy.ci_deny_data_reads.arn
}

data "aws_iam_policy_document" "ci_plan_state_lock" {
  statement {
    sid       = "ManageEnvStateLocks"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/envs/*/terraform.tfstate.tflock"]
  }
}

resource "aws_iam_role_policy" "ci_plan_state_lock" {
  name   = "aigt-ci-plan-state-lock"
  role   = aws_iam_role.ci_plan.id
  policy = data.aws_iam_policy_document.ci_plan_state_lock.json
}
