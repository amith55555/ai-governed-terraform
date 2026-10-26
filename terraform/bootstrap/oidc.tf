locals {
  github_owner = split("/", var.github_repository)[0]
  github_repo  = split("/", var.github_repository)[1]

  # GitHub OIDC subject with immutable IDs, e.g.
  # repo:amith55555@97042431/ai-governed-terraform@1431221190
  github_sub_prefix = "repo:${local.github_owner}@${var.github_owner_id}/${local.github_repo}@${var.github_repository_id}"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
