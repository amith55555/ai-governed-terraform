locals {
  environments   = toset(["dev", "prod"])
  region_account = "${var.region}:${var.aws_account_id}"
}

data "aws_iam_policy_document" "ci_apply_trust" {
  for_each = local.environments

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
      values   = ["${local.github_sub_prefix}:environment:${each.key}"]
    }
  }
}

resource "aws_iam_role" "ci_apply" {
  for_each = local.environments

  name                 = "aigt-ci-apply-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.ci_apply_trust[each.key].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "ci_apply_readonly" {
  for_each = local.environments

  role       = aws_iam_role.ci_apply[each.key].name
  policy_arn = local.readonly_policy_arn
}

resource "aws_iam_role_policy_attachment" "ci_apply_deny_data" {
  for_each = local.environments

  role       = aws_iam_role.ci_apply[each.key].name
  policy_arn = aws_iam_policy.ci_deny_data_reads.arn
}

data "aws_iam_policy_document" "ci_apply_write" {
  for_each = local.environments

  statement {
    sid       = "EnvState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/envs/${each.key}/*"]
  }

  statement {
    sid     = "DenyOtherEnvState"
    effect  = "Deny"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.state.arn}/envs/${each.key == "dev" ? "prod" : "dev"}/*"
    ]
  }

  statement {
    sid       = "Tables"
    actions   = ["dynamodb:*"]
    resources = ["arn:aws:dynamodb:${local.region_account}:table/aigt-${each.key}-*"]
  }

  statement {
    sid     = "Buckets"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::aigt-${each.key}-*",
      "arn:aws:s3:::aigt-${each.key}-*/*",
    ]
  }

  statement {
    sid       = "Functions"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:${local.region_account}:function:aigt-${each.key}-*"]
  }

  statement {
    sid     = "LogGroups"
    actions = ["logs:*"]
    resources = [
      "arn:aws:logs:${local.region_account}:log-group:/aws/lambda/aigt-${each.key}-*",
      "arn:aws:logs:${local.region_account}:log-group:/aws/lambda/aigt-${each.key}-*:*",
      "arn:aws:logs:${local.region_account}:log-group:/aws/apigateway/aigt-${each.key}-*",
      "arn:aws:logs:${local.region_account}:log-group:/aws/apigateway/aigt-${each.key}-*:*",
    ]
  }

  statement {
    sid = "ApiAccessLogDelivery"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }

  statement {
    sid = "AlarmsAndTopics"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "sns:*",
    ]
    resources = [
      "arn:aws:cloudwatch:${local.region_account}:alarm:aigt-${each.key}-*",
      "arn:aws:sns:${local.region_account}:aigt-${each.key}-*",
    ]
  }

  statement {
    sid = "HttpApis"
    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
    ]
    resources = [
      "arn:aws:apigateway:${var.region}::/apis",
      "arn:aws:apigateway:${var.region}::/apis/*",
      "arn:aws:apigateway:${var.region}::/tags/*",
    ]
  }

  statement {
    sid = "RolesOnlyWithBoundary"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/aigt-${each.key}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid = "ManageOwnRoles"
    actions = [
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/aigt-${each.key}-*"]
  }

  statement {
    sid       = "PassOwnRolesToLambdaOnly"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.aws_account_id}:role/aigt-${each.key}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "ProtectBoundary"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:PutRolePermissionsBoundary",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:DeletePolicy",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_apply_write" {
  for_each = local.environments

  name   = "aigt-ci-apply-${each.key}-write"
  role   = aws_iam_role.ci_apply[each.key].id
  policy = data.aws_iam_policy_document.ci_apply_write[each.key].json
}
