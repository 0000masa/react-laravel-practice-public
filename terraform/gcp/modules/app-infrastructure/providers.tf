# =============================================================================
# モジュール用 providers.tf
# =============================================================================
# このモジュールは google / google-beta の2プロバイダを「受け取る」と宣言する側。
# リージョンや認証情報の指定は stg/providers.tf 側で行う。
# =============================================================================

terraform {
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
}
