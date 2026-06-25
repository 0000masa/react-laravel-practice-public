variable "pr_number" {
  description = "対象の PR 番号。全リソースの命名とサブドメイン・優先度に使う。"
  type        = number
}

variable "project_name" {
  description = "stg と揃えるプロジェクト名（命名プレフィックス）"
  type        = string
  default     = "practice-stg"
}

variable "image_tag_nginx" {
  description = "PR の nginx イメージタグ（ECR）"
  type        = string
}

variable "image_tag_laravel" {
  description = "PR の laravel イメージタグ（ECR）"
  type        = string
}

variable "mail_preview_redirect_to" {
  description = "preview の全メール宛先を上書きする固定アドレス（MAIL_PREVIEW_REDIRECT_TO）"
  type        = string
}

# stg の state（remote_state で参照）
variable "stg_state_bucket" {
  type    = string
  default = "github-action-terraform-tf-state-bucket"
}

variable "stg_state_key" {
  type    = string
  default = "practice/laravel/stg/terraform.tfstate"
}

# preview タスクのサイズ（小さめ）
variable "task_cpu" {
  type    = string
  default = "512"
}

variable "task_memory" {
  type    = string
  default = "1024"
}
