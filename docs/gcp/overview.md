# Google Cloud 版（Cloud Run / VPCなし・コア構成）

AWS 版（`terraform/`）の Laravel + React アプリを Google Cloud に最小構成で載せ替えるための
Terraform コード（`terraform/gcp/`）の概要。設計判断の記録は
[`0001-gcp-cloudrun-novpc-core.md`](../adr/0001-gcp-cloudrun-novpc-core.md)。

学習フローは **「Google Cloud コンソールで手作業作成 → `terraform import` でコード化」**。
`terraform/gcp/` の `.tf` はその import 先（ターゲット）として書いてある。
イメージ push **だけ** は GitHub Actions で行い、それ以外はコンソールで作る（gcloud CLI は使わない）。

## 関連ドキュメント

- [manual-setup-console.md](./manual-setup-console.md) — コンソール手動作成 → import の手順（メイン）
- [github-actions-image-push.md](./github-actions-image-push.md) — Artifact Registry へのイメージ push（GHA + WIF）
- [aws-vs-gcp-org-project.md](./aws-vs-gcp-org-project.md) — アカウント / プロジェクト / 組織モデルの AWS 対比

## 構成（AWS → GCP マッピング）

| AWS | GCP |
| --- | --- |
| CloudFront + S3(OAC) | 外部 HTTPS LB + Cloud CDN + GCS バックエンドバケット |
| CloudFront `/api/*` → ALB | 同一 LB の URL マップ `/api/*` → Serverless NEG → Cloud Run |
| ALB 403 + 秘密ヘッダー | Cloud Run ingress = `INTERNAL_LOAD_BALANCER`（run.app 直叩き遮断） |
| 画像用 CloudFront + 非公開 S3 | LB の追加バックエンドバケット + Cloud CDN（公開 read GCS） |
| ECS Fargate（nginx + php-fpm） | Cloud Run マルチコンテナ（nginx ingress + php-fpm サイドカー） |
| ECS タスクロール | Cloud Run 実行 SA + ADC（キーレス） |
| RDS MariaDB | Cloud SQL for MySQL 8.0（公開 IP + コネクタ、VPCなし） |
| SSM Parameter Store | Secret Manager（db_password / app_key / google_client_id / google_client_secret） |
| ECR（nginx / laravel の2リポジトリ） | Artifact Registry（nginx / laravel の2リポジトリ） |
| ECS RunTask（migrate） | Cloud Run Job |
| GitHub OIDC ロール（用途別） | Workload Identity Federation + デプロイ SA（リポジトリ別・最小権限） |
| GitHub Actions → ECR push | GitHub Actions → Artifact Registry push（イメージ push のみ） |
| SQS / EventBridge / SES / Queue Worker | **コア対象外**（後日フル版で別ディレクトリ） |

## ディレクトリ

```
terraform/gcp/
├── modules/app-infrastructure/   # 本体（AWS 版と同じ modules/env 分割）
│   ├── artifact_registry.tf      # nginx / laravel の2リポジトリ
│   ├── ci.tf                     # WIF + デプロイ SA（GitHub Actions 用）
│   └── ...                       # cloud_run / cloud_sql / load_balancer / gcs / dns ほか
└── stg/                          # 環境（GCS backend / tfvars / imports.tf）
```

## アプリ側に必要な変更（インフラ外・別途実施）

- `composer require league/flysystem-google-cloud-storage`（または `superbalist/laravel-google-cloud-storage`）
- `config/filesystems.php` に `gcs` ディスクを追加（`FILESYSTEM_DISK=gcs` で使用）
- DB 接続を Unix ソケット対応に（`config/database.php` の mysql 接続が `DB_SOCKET` を見るようにする）
- nginx / laravel イメージの push は GitHub Actions で行う（[github-actions-image-push.md](./github-actions-image-push.md)）。
  push 後に `terraform.tfvars` の `image_tag_nginx` / `image_tag_laravel` をそのタグ（`sha-<SHA>`）に更新する。

## 進め方

1. コンソールで各リソースを手動作成 → import（[manual-setup-console.md](./manual-setup-console.md)）
2. GitHub Actions でイメージを push（[github-actions-image-push.md](./github-actions-image-push.md)）
3. `terraform.tfvars` のイメージタグ更新 → `terraform apply` で Cloud Run の参照を更新

import コマンドの流れと各リソースの id テンプレートは
`terraform/gcp/stg/imports.tf` と [manual-setup-console.md](./manual-setup-console.md) を参照。

## 注意点

- **Google マネージド SSL 証明書**は、対象ドメインが LB の IP に解決し DNS 委譲が効くまで `ACTIVE` にならない。
  仮ドメイン段階では `PROVISIONING` のまま。本番ドメイン取得 → レジストラを Cloud DNS の NS（`terraform output dns_name_servers`）に委譲 → A レコードが LB IP（`terraform output lb_ip_address`）を指す、で発行される。
- **DoS によるデータ転送課金**は Cloud CDN だけでは止まらない（エッジ egress は課金される）。本気で抑えるなら
  Cloud Armor（レート制限）を LB に追加する。コア構成では未実装＝予算アラートで補う。
- Cloud SQL は公開 IP だが `authorized_networks` を開けていないため、コネクタ（IAM/SSL 認証）以外からは接続不可。
- `db_password` は Terraform が生成・投入する（`random_password` + `secret_version`）。`app_key` /
  `google_client_id` / `google_client_secret` は値が外部由来なので、シークレットの箱を import した上で
  値（バージョン）をコンソールで手動追加する。
