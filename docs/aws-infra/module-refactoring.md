# Terraform モジュール共通化ドキュメント

## 概要

`stg/` フォルダにあった23個の `.tf` ファイルを単一モジュール `modules/app-infrastructure/` に共通化した。
将来 `prod/` 環境を作成する際に、最小限のファイル（`providers.tf`, `variables.tf`, `main.tf`, `terraform.tfvars`）だけで済むようにすることが目的。

## アプローチ: 単一モジュール

リソース間の依存が非常に多い（ECS が RDS, S3, CloudFront, CloudWatch 等を参照）ため、**単一の大きなモジュール**を採用した。
複数モジュールに分割すると output/variable の受け渡しが膨大になり、複雑になるだけでメリットが少ない。

## ディレクトリ構成

```
s3-laravel-terraform-BGD/
├── modules/
│   └── app-infrastructure/
│       ├── providers.tf        # configuration_aliases のみ（provider定義なし）
│       ├── data.tf             # data sources (SSM, CloudFront policies, caller identity, archive)
│       ├── vpc.tf              # VPC module + VPC endpoint
│       ├── security_groups.tf  # ALB/ECS/RDS 用セキュリティグループ
│       ├── rds.tf              # RDS インスタンス + サブネットグループ
│       ├── alb.tf              # ALB + リスナー + ターゲットグループ + リスナールール
│       ├── acm.tf              # ACM 証明書 (frontend/backend) + validation
│       ├── s3.tf               # S3 バケット (frontend/images) + バケットポリシー
│       ├── cloudfront.tf       # CloudFront ディストリビューション + OAC + SPA fallback
│       ├── ecs_web.tf          # ECS クラスタ + Web サービス + タスク定義 + オートスケーリング
│       ├── ecs_queue.tf        # ECS キューワーカーサービス + タスク定義
│       ├── ecs_tasks.tf        # ECS タスク定義 (migration/seeder/batch)
│       ├── iam.tf              # IAM ロール (5つ) + IAM ポリシー (8つ)
│       ├── lambda.tf           # Lambda 関数 (通知) + ソースコード + 権限
│       ├── cloudwatch.tf       # CloudWatch ロググループ + サブスクリプションフィルター + アラーム
│       ├── route53.tf          # Route53 レコード (frontend/backend/cert validation/SES関連)
│       ├── ses.tf              # SES ドメイン + DKIM + MAIL FROM
│       ├── sns.tf              # SNS トピック + サブスクリプション
│       ├── sqs.tf              # SQS キュー (QRコード非同期生成)
│       ├── event_bridge.tf     # EventBridge ルール + ターゲット (日次バッチ)
│       ├── ssm.tf              # SSM パラメータストア (GitHub Actions 連携用)
│       ├── waf.tf              # WAF Web ACL + random_password
│       └── variables.tf        # モジュール入力変数
├── stg/
│   ├── providers.tf            # そのまま維持（backend設定 + provider定義）
│   ├── variables.tf            # そのまま維持
│   ├── main.tf                 # NEW: モジュール呼び出し
│   ├── moved.tf                # NEW: moved ブロック（state移行用）
│   ├── terraform.tfvars        # そのまま維持
│   └── .terraform.lock.hcl     # そのまま維持
└── docs/
    └── module-refactoring.md   # 本ドキュメント
```

## 変更内容の詳細

### ファイル名の変更

| 旧ファイル名 (stg/) | 新ファイル名 (modules/) | 理由 |
|---|---|---|
| `ecs_que.tf` | `ecs_queue.tf` | 省略形を正式名に |
| `ecs-task.tf` | `ecs_tasks.tf` | ハイフンをアンダースコアに統一、複数形に |
| `parameter.tf` | `ssm.tf` | AWS サービス名に合わせて |

### ファイルの統合

| 統合先 | 統合元 | 理由 |
|---|---|---|
| `iam.tf` | `iam_role.tf` + `iam_policy.tf` | ロールとポリシーは密結合 |

### providers.tf が2つある理由

`stg/providers.tf` と `modules/app-infrastructure/providers.tf` は名前が同じだが、**役割が異なる**。

| ファイル | 役割 |
|---|---|
| `stg/providers.tf` | `provider` ブロック（リージョン指定）+ `backend` ブロック（state保存先）を**定義する側** |
| `modules/app-infrastructure/providers.tf` | モジュールが「`aws` と `aws.us_east_1` の2つの provider を受け取る」と**宣言する側**（`configuration_aliases`） |

モジュール内の `acm.tf` と `waf.tf` で `provider = aws.us_east_1` を指定しているため、モジュール側にこの宣言がないとエラーになる。**モジュール側の providers.tf は削除してはいけない。**

#### modules/app-infrastructure/providers.tf の内容

```hcl
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.6"
      configuration_aliases = [aws.us_east_1]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
```

- `provider` ブロックは書かない（呼び出し元から渡す）
- `configuration_aliases` で `aws.us_east_1` を宣言（ACM, WAF 用にバージニアリージョンが必要）

#### stg/main.tf で provider を渡す

```hcl
providers = {
  aws           = aws           # デフォルト (ap-northeast-1)
  aws.us_east_1 = aws.us_east_1 # バージニア (us-east-1)
}
```

この仕組みにより、モジュール自体は provider を定義せず、呼び出し元（stg/ や将来の prod/）から渡された provider を使う。

### stg/main.tf（モジュール呼び出し）

```hcl
module "app" {
  source = "../modules/app-infrastructure"

  project_name             = var.project_name
  domain_name              = var.domain_name
  sub_frontend_domain_name = var.sub_frontend_domain_name
  sub_backend_domain_name  = var.sub_backend_domain_name
  db_name                  = var.db_name
  db_username              = var.db_username
  parameter_store_path     = var.parameter_store_path
  image_tag                = var.image_tag
  enable_nat_gateway       = var.enable_nat_gateway
  app_env                  = var.app_env

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

## State 移行（moved ブロック）

### moved.tf とは

モジュール化により、Terraform state 内のリソースアドレスが変わる。

```
# before
aws_db_instance.main

# after
module.app.aws_db_instance.main
```

moved ブロックがないと、Terraform は「旧アドレスのリソースを destroy して、新アドレスで create する」と判断してしまう。moved ブロックがあれば、state 内のアドレスだけ書き換わり、AWS 上の実リソースには何も起きない。

### state 移行のタイミング

state の移動は **`terraform apply` ではなく `terraform plan` の時点で実行される**。

1. `terraform init` — モジュールソースを読み込む
2. `terraform plan` — **ここで state 内のアドレスが書き換わる**。plan 出力に `has moved to` と表示される
3. plan の結果は `0 adds, 0 changes, 0 destroys` になる

つまり `terraform apply` は不要で、`terraform plan` だけで state 移行が完了する。

### まだ terraform apply をしていない場合

state にリソースが存在しないため、**moved.tf は不要**。ファイルごと削除して問題ない。

### moved ブロックの詳細

`stg/moved.tf` に約80個の `moved` ブロックを定義し、既存リソースの state を `module.app` 配下に移行する。

### moved ブロックの分類

| カテゴリ | 件数 | 例 |
|---|---|---|
| 通常リソース | 約65個 | `aws_db_instance.main` → `module.app.aws_db_instance.main` |
| モジュール | 5個 | `module.vpc` → `module.app.module.vpc` |
| `for_each` リソース | 2個 | `aws_route53_record.cert_validation_frontend["www.favoritemyanime.com"]` → `module.app.aws_route53_record.cert_validation_frontend["www.favoritemyanime.com"]` |
| `count` リソース | 3個 | `aws_route53_record.ses_dkim_records[0]` → `module.app.aws_route53_record.ses_dkim_records[0]` |

### for_each リソースのキーについて

`cert_validation_frontend` と `cert_validation_backend` は `for_each` を使っているため、moved ブロックのキーは実際の state と一致している必要がある。

現在の推定キー:
- `cert_validation_frontend`: `"www.favoritemyanime.com"`
- `cert_validation_backend`: `"api.favoritemyanime.com"`

**もしキーが異なる場合は、以下のコマンドで確認して修正すること:**

```bash
cd stg/
terraform state list | grep cert_validation
```

## 検証手順

```bash
cd stg/

# 1. モジュールソースの再初期化
terraform init

# 2. plan で変更がないことを確認
terraform plan
```

### 期待される結果

- `terraform init`: 成功（新しいモジュールソースが読み込まれる）
- `terraform plan`: **0 adds, 0 changes, 0 destroys** + moved の表示のみ

### もし plan で差分が出た場合

1. **destroy/create が表示される**: moved ブロックのキーが間違っている可能性。`terraform state list` で実際のリソースアドレスを確認
2. **`path.module` 関連の変更**: `lambda.tf` の `local_file` と `data.archive_file` が `path.module` を使用。`lifecycle { ignore_changes }` が設定されているため plan 上は影響なしだが、もし差分が出た場合は apply して問題ない

## 注意点

### path.module の変化

`lambda.tf` の `local_file` と `data.archive_file` が `path.module` を使用しているため、モジュール移動後は `.tmp/` の場所が `stg/.tmp/` から `modules/app-infrastructure/.tmp/` に変わる。

ただし Lambda 関数には `lifecycle { ignore_changes = [filename, source_code_hash] }` が設定されているため、plan 上は影響なし。

### .gitignore

`stg/.gitignore` に以下を追加済み:

```
../modules/app-infrastructure/.tmp/
```

## 将来の prod 環境作成方法

`prod/` フォルダに以下の4ファイルを作成するだけ:

```
prod/
├── providers.tf      # backend key を prod 用に変更
├── variables.tf      # stg と同一
├── main.tf           # stg と同一（source パスも同じ "../modules/app-infrastructure"）
└── terraform.tfvars  # 本番用の値
```

### prod/providers.tf の例

```hcl
terraform {
  required_version = "~> 1.14.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  backend "s3" {
    bucket       = "github-action-terraform-tf-state-bucket"
    key          = "kum/prod/firelens/terraform.tfstate"  # ← prod 用のキー
    region       = "ap-northeast-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```

### prod/terraform.tfvars の例

```hcl
project_name             = "kum-prod"
domain_name              = "favoritemyanime.com"
sub_frontend_domain_name = "app"           # 本番用サブドメイン
sub_backend_domain_name  = "api-prod"      # 本番用サブドメイン
db_name                  = "kum_db"
db_username              = "admin"
parameter_store_path     = "/kum/prod/"
image_tag                = "latest"
app_env                  = "production"
```

**注意**: prod では `moved.tf` は不要（新規作成のため）。
