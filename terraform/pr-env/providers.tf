terraform {
  required_version = "~> 1.14.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.6"
    }
  }

  # backend は partial 設定。key は PR ごとに -backend-config で差し替える。
  #   terraform init -backend-config=pr-env.tfbackend \
  #                  -backend-config="key=preview/pr-<n>/terraform.tfstate"
  backend "s3" {}
}

provider "aws" {
  region = "ap-northeast-1"
}
