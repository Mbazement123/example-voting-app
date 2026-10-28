terraform {
  backend "s3" {
    bucket = "example-voting-app-terraform-state-011528257636-eu-north-1"
    key    = "example-voting-app/eu-north-1/terraform.tfstate"
    region = "eu-north-1"
  }
}
