terraform {
  backend "s3" {
    bucket       = "aigt-tfstate-ca075457"
    key          = "envs/prod/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
