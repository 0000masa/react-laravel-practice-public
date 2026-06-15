# 環境変数設定ガイド

## 概要

このアプリケーションは、開発環境と本番環境（AWS ECS）で異なるストレージとメールサービスを使用します。環境変数で簡単に切り替えが可能です。

- **開発環境**: MinIO（オブジェクトストレージ）+ Mailpit（メールテスト）
- **本番環境**: AWS S3（オブジェクトストレージ）+ AWS SES（メール送信）

## 環境変数の設定

### 開発環境（MinIO + Mailpit）

`.env`ファイルに以下の設定を追加してください：

```env
# ストレージ設定（MinIO）
STORAGE_DISK=minio
FILESYSTEM_DISK=minio
AWS_ACCESS_KEY_ID=minio_root
AWS_SECRET_ACCESS_KEY=minio_password
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=qrcodes
AWS_USE_PATH_STYLE_ENDPOINT=true
AWS_ENDPOINT=http://minio:9000

# メール設定（Mailpit）
MAIL_MAILER=smtp
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_FROM_ADDRESS=hello@example.com
MAIL_FROM_NAME="${APP_NAME}"
```

### 本番環境（AWS S3 + SES）

> **重要 — 静的アクセスキーは使わない**: 本番（ECS Fargate）では `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` を**設定しません**。ECS の **タスクロール**（`practice-stg-task-role`、`terraform/modules/app-infrastructure/iam.tf` で S3 / SES / SQS を最小権限にスコープ）に紐づくコンテナクレデンシャルを AWS SDK が自動取得します。実際の ECS タスク定義（`ecspresso/stg/web/ecs-task-def.jsonnet` / `ecspresso/_common.libsonnet`）にもアクセスキーは含めていません。静的キーを持たないことで漏洩リスクとローテーション運用を排除しています。

AWS ECS のタスク定義では以下の値を設定します（アクセスキーは含めない）：

```env
# ストレージ設定（AWS S3）— 認証はタスクロールに委譲
STORAGE_DISK=s3
FILESYSTEM_DISK=s3
AWS_DEFAULT_REGION=<AWS_REGION>
AWS_BUCKET=<S3_BUCKET_NAME>
AWS_USE_PATH_STYLE_ENDPOINT=false
AWS_ENDPOINT=
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY は設定しない（タスクロールを使用）

# メール設定（AWS SES）
MAIL_MAILER=ses
MAIL_FROM_ADDRESS=<VERIFIED_EMAIL_ADDRESS>
MAIL_FROM_NAME="${APP_NAME}"
```

## 環境変数の説明

### ストレージ関連

| 変数名 | 説明 | 開発環境 | 本番環境 |
|--------|------|----------|----------|
| `STORAGE_DISK` | QRコード保存に使用するディスク | `minio` | `s3` |
| `FILESYSTEM_DISK` | Laravelのデフォルトディスク | `minio` | `s3` |
| `AWS_ACCESS_KEY_ID` | AWS/MinIOのアクセスキー | `minio_root` | AWS IAMユーザーのアクセスキー |
| `AWS_SECRET_ACCESS_KEY` | AWS/MinIOのシークレットキー | `minio_password` | AWS IAMユーザーのシークレットキー |
| `AWS_DEFAULT_REGION` | AWSリージョン | `us-east-1` | 使用するAWSリージョン（例: `ap-northeast-1`） |
| `AWS_BUCKET` | バケット名 | `qrcodes` | S3バケット名 |
| `AWS_USE_PATH_STYLE_ENDPOINT` | パススタイルエンドポイントを使用 | `true` | `false` |
| `AWS_ENDPOINT` | エンドポイントURL | `http://minio:9000` | 空（S3のデフォルトエンドポイントを使用） |

### メール関連

| 変数名 | 説明 | 開発環境 | 本番環境 |
|--------|------|----------|----------|
| `MAIL_MAILER` | メール送信に使用するドライバー | `smtp` | `ses` |
| `MAIL_HOST` | SMTPホスト（smtp使用時） | `mailpit` | - |
| `MAIL_PORT` | SMTPポート（smtp使用時） | `1025` | - |
| `MAIL_USERNAME` | SMTPユーザー名（smtp使用時） | `null` | - |
| `MAIL_PASSWORD` | SMTPパスワード（smtp使用時） | `null` | - |
| `MAIL_FROM_ADDRESS` | 送信元メールアドレス | `hello@example.com` | SESで検証済みのメールアドレス |
| `MAIL_FROM_NAME` | 送信元名 | `${APP_NAME}` | `${APP_NAME}` |

## セットアップ手順

### 開発環境のセットアップ

1. **MinIOのセットアップ**
   - `docker-compose.yml`でMinIOコンテナが起動します
   - MinIOコンソール（http://localhost:9090）にアクセス
   - ログイン情報: `minio_root` / `minio_password`
   - `qrcodes`バケットを作成
   - 詳細は [minio_setup.md](minio_setup.md) を参照

2. **Mailpitのセットアップ**
   - `docker-compose.yml`でMailpitコンテナが起動します
   - Mailpit Web UI（http://localhost:8025）でメールを確認できます
   - 詳細は [mailpit_setup.md](mailpit_setup.md) を参照

3. **環境変数の設定**
   - `environment/laravel/.env`に上記の開発環境用設定を追加

### 本番環境（AWS ECS）のセットアップ

1. **S3バケットの作成**
   - AWSコンソールでS3バケットを作成
   - 適切なIAMポリシーを設定（読み書き権限）

2. **SESの設定**
   - AWS SESでメールアドレスまたはドメインを検証
   - 必要に応じてサンドボックス環境の制限を解除
   - IAMユーザーにSES送信権限を付与

3. **ECS タスクロールの権限付与**（IAM ユーザー＋アクセスキーは作らない）
   - S3 / SES / SQS へのアクセスは ECS タスクロール（`*-task-role`）に付与する。Terraform（`iam.tf` / `iam_policy.tf`）で最小権限ポリシーを定義済み
   - 静的アクセスキーを発行・配布しないため、漏洩リスクとローテーション運用が不要

4. **ECSタスク定義の設定**
   - 環境変数に上記の本番環境用設定を追加（アクセスキーは含めない）
   - `DB_PASSWORD` / `APP_KEY` などの機密値は SSM Parameter Store の SecureString を `secrets[].valueFrom` で参照（実装済み）

## 動作確認

### QRコードアップロードの確認

1. アプリケーションでQRコードを生成
2. **開発環境**: MinIOコンソールで`qrcodes`バケットにファイルが保存されていることを確認
3. **本番環境**: S3コンソールでバケットにファイルが保存されていることを確認

### メール送信の確認

1. アプリケーションでメールを送信
2. **開発環境**: Mailpit Web UI（http://localhost:8025）でメールが受信されていることを確認
3. **本番環境**: 実際のメールアドレスにメールが届くことを確認

## トラブルシューティング

### MinIO接続エラー

- MinIOコンテナが起動しているか確認: `docker ps`
- ネットワーク設定を確認: `docker-compose.yml`で`backend`ネットワークに接続されているか
- エンドポイントURLを確認: `AWS_ENDPOINT=http://minio:9000`

### Mailpit接続エラー

- Mailpitコンテナが起動しているか確認: `docker ps`
- ポート1025が正しく設定されているか確認
- ネットワーク設定を確認

### S3接続エラー（本番環境）

- IAMユーザーの権限を確認
- リージョンが正しいか確認
- バケット名が正しいか確認
- `AWS_USE_PATH_STYLE_ENDPOINT=false`に設定されているか確認

### SES送信エラー（本番環境）

- メールアドレスまたはドメインが検証されているか確認
- IAMユーザーにSES送信権限があるか確認
- サンドボックス環境の制限を確認（未検証のメールアドレスへの送信は制限される）

## 参考資料

- [MinIOセットアップガイド](minio_setup.md)
- [Mailpitセットアップガイド](mailpit_setup.md)
- [Laravel Filesystem Documentation](https://laravel.com/docs/filesystem)
- [Laravel Mail Documentation](https://laravel.com/docs/mail)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [AWS SES Documentation](https://docs.aws.amazon.com/ses/)








