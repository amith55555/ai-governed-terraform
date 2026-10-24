provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "bootstrap"
      Repo      = "amith55555/ai-governed-terraform"
    }
  }
}
