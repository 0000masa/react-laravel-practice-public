terraform {
  required_version = "~> 1.14.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # state は GCS バケットに保存（AWS の S3 backend 相当）。
  # バケットは事前に手動作成しておく（README のブートストラップ参照）。
  backend "gcs" {
    bucket = "practice-gcp-tfstate" # 手動作成した GCS バケット名に合わせる
    prefix = "practice/laravel/gcp/stg"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
