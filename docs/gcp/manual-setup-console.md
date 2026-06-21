# GCP コンソール手動作成 → terraform import 手順

このプロジェクトの方針は **「Google Cloud コンソールで手作業作成 → `terraform import` でコード化」**。
イメージ push **だけ** は GitHub Actions（[別ドキュメント](./github-actions-image-push.md)）で、
それ以外のリソースはすべて**コンソール画面**で作る（gcloud CLI は使わない）。

- 作成するリソースの **名前・設定値は `terraform/gcp/` の `.tf` と一致**させる。一致していれば
  import 後の `terraform plan` が差分ゼロに近づく。
- import 用のアドレスと id テンプレートは `terraform/gcp/stg/imports.tf` にある。
  コンソールで作ったら該当ブロックのコメントを外し、`terraform apply` で取り込む。
- 名前のプレフィックスは `terraform.tfvars` の `project_name`（= `practice-gcp-stg`）。
- リージョンは `asia-northeast1`。

> import 後に差分が出たら、`.tf` 側かコンソール設定のどちらかを寄せて収束させる。
> 新規作成で済ませたいリソースは import ブロックを書かず、そのまま `apply` で作ってもよい。

---

## 0. 前提

1. GCP プロジェクトを用意し、課金を有効化（コンソール: 「お支払い」）。
2. `terraform/gcp/stg/terraform.tfvars` の `project_id` を実際の ID に置換。

## 1. state 用 GCS バケット（Terraform backend）

`terraform/gcp/stg/providers.tf` の `backend "gcs"` と一致させる。

- コンソール: **Cloud Storage → バケット → 作成**
  - 名前: `practice-gcp-tfstate`
  - ロケーション: `asia-northeast1`（Region）
  - アクセス制御: **均一（uniform）**
- これは Terraform の state 置き場なので import 対象ではない。作成後 `terraform init` する。

## 2. API の有効化

コンソール: **API とサービス → 有効なAPIとサービス → APIとサービスの有効化** で以下を有効化。

| サービス名（エンドポイント） | コンソールで検索する正式名称 |
| --- | --- |
| `run.googleapis.com` | Cloud Run Admin API |
| `sqladmin.googleapis.com` | Cloud SQL Admin API |
| `secretmanager.googleapis.com` | Secret Manager API |
| `artifactregistry.googleapis.com` | Artifact Registry API |
| `compute.googleapis.com` | Compute Engine API |
| `dns.googleapis.com` | Cloud DNS API |
| `iam.googleapis.com` | Identity and Access Management (IAM) API |
| `iamcredentials.googleapis.com` | IAM Service Account Credentials API |
| `sts.googleapis.com` | Security Token Service API |

> **サービス名とコンソール表示名は一致しない**。コンソールの「API とサービスの有効化」では
> 右列の正式名称で検索する。Terraform（`google_project_service`）や import id では左列の
> エンドポイント名（例 `run.googleapis.com`）を使う。`run` は「Cloud Run 本体」ではなく
> Cloud Run を**管理操作するための Admin API** を指す点に注意。

GCP では各サービス（API）が**プロジェクトごとにデフォルト無効**で、使う前にこのスイッチを
ON にしないとリソース作成が `API not enabled` で弾かれる。だから手順3以降より先に行う
（有効化自体は無料。課金は実使用分のみ）。

> **AWS との違い**: AWS には基本この概念がない。EC2/S3/RDS などはアカウント作成時から使え、
> 「サービスを使う前に有効化する」ゲートがない（アクセス可否は IAM で制御）。
> 強いて近いのは GuardDuty / Security Hub / AWS Config やオプトインリージョンの「有効化」操作だが、
> あれは一部サービスだけ。GCP は**全サービスがこのオプトイン方式**と捉えるのが正確。

> `apis.tf` の `google_project_service.apis`（for_each）に対応。import id は `<PROJECT_ID>/<service>`。

## 3. Artifact Registry リポジトリ（2つ）

コンソール: **Artifact Registry → リポジトリを作成** を2回。

| repository_id | 形式 | リージョン |
| --- | --- | --- |
| `nginx` | Docker | asia-northeast1 |
| `laravel` | Docker | asia-northeast1 |

> `artifact_registry.tf` の `google_artifact_registry_repository.repos["nginx"|"laravel"]`。

## 4. Secret Manager（4 シークレット）

コンソール: **Secret Manager → シークレットを作成**。レプリケーションは「自動」。

| シークレット名 | 値（バージョン） |
| --- | --- |
| `practice-gcp-stg-db-password` | **空のままでよい**（値は Terraform が生成・投入する） |
| `practice-gcp-stg-app-key` | `php artisan key:generate --show` の値を「新しいバージョン」で追加 |
| `practice-gcp-stg-google-client-id` | Google OAuth クライアント ID |
| `practice-gcp-stg-google-client-secret` | Google OAuth クライアントシークレット |

> `secret_manager.tf`。`db_password` は `random_password` + `secret_version` が **Terraform 管理**。
> よって db-password は**シークレットの箱だけ**コンソールで作って import し、値（バージョン）は
> `terraform apply` 時に TF が投入する。残り3つは箱を import し、値は手動でバージョン追加する。

## 5. Cloud SQL（MySQL 8.0）

コンソール: **SQL → インスタンスを作成 → MySQL**。

- インスタンス ID: `practice-gcp-stg-mysql` / バージョン: **MySQL 8.0**
- エディション: **Enterprise**（`db-f1-micro` などの共有コアは Enterprise 専用。Enterprise Plus は専有コアが前提で選べない）
- エディションのプリセット: **サンドボックス**（最安・単一ゾーン。プリセットは初期値を埋めるだけなので、選択後に以下の値へ寄せる）
- リージョン: `asia-northeast1` / 可用性: **単一ゾーン**
- マシン: 共有コア **db-f1-micro** / ストレージ: SSD 10GB
- 接続: **パブリック IP を有効**、**承認済みネットワークは追加しない**（コネクタ専用）
- バックアップ: 無効（practice 設定）
- 作成後: **データベース** `practice_db`（文字セット `utf8mb4` / 照合 `utf8mb4_unicode_ci`）、
  **ユーザー** `admin`（パスワードは仮で可。import 後の `apply` で TF 生成値に上書きされる）

> `cloud_sql.tf`。`google_sql_database_instance.main` / `google_sql_database.main` / `google_sql_user.main`。
> ユーザーパスワードは `db_password` シークレットと同じ値（TF 管理）に収束する。

## 6. Cloud Run 実行サービスアカウント + 権限

コンソール: **IAM と管理 → サービスアカウント → 作成**。

- SA: `practice-gcp-stg-run`（表示名は任意）
- ロール付与:
  - プロジェクトに **Cloud SQL クライアント**（`roles/cloudsql.client`）
  - 各シークレット（4つ）に **Secret Manager のシークレット アクセサー**（シークレットの権限タブで付与）
  - 画像バケット（手順7）に **Storage オブジェクト管理者**（`roles/storage.objectAdmin`）

> **「付与する場所」がそのままスコープになる（重要）**
> GCP IAM の権限は `プリンシパル × ロール × リソース` のバインディングで、**リソース（または
> project / folder / org の上位階層）側の IAM ポリシーに格納される**。GCP には「プリンシパル（SA）側に
> ポリシーを貼る」概念が無いので、付与は常に**リソース側で行う**。したがって**どのリソースで付与するかが
> そのまま権限スコープ**になる。
>
> - **シークレット アクセサーを各シークレットの「権限」タブで付与** → そのバインディングはそのシークレット
>   1個にしか存在しない → **そのシークレットだけ**読める（＝最小権限）。**プロジェクトの IAM 画面**で
>   同じロールを付けると**全シークレット**が読めてしまうので避ける。
>   - 手順: Secret Manager → 対象シークレットを開く → **権限タブ → アクセスを許可** →
>     プリンシパル `practice-gcp-stg-run@<PROJECT_ID>.iam.gserviceaccount.com`、ロール
>     `roles/secretmanager.secretAccessor` → 保存。これを **4シークレット分**繰り返す。
>   - 粒度はシークレット単位まで（特定バージョンだけには絞れない）。`secretAccessor` は**値の読み取り専用**。
> - 同様に `Cloud SQL クライアント` は**プロジェクト**に、`Storage オブジェクト管理者` は**画像バケット単体**に
>   付与している（手順7）。3つで付与先の階層が違うのは、それぞれ必要な最小スコープに合わせているため。
>
> **AWS との違い**: AWS は通常 **IAM ロール（プリンシパル側）に identity ポリシーを貼って終わり**で、
> リソース側は触らない。リソース側のポリシー（S3 バケットポリシー / KMS キーポリシー / Secrets Manager の
> リソースポリシー）は**任意の追加層**（Parameter Store には無い）。一方 **GCP はプリンシパル側に貼る手段が
> 無く、リソース側 IAM が唯一の手段**。「SA にロールを付与」と「シークレット側で許可」は**別操作ではなく
> 同じ1個のバインディング**であり、二重設定ではない。
> IAM モデル全体（ロール3種 / バインディング / SA のトラスト側 / AWS 比較）は
> [iam-aws-gcp.md](./iam-aws-gcp.md) にまとめている。

> `service_account.tf`。シークレットは `google_secret_manager_secret_iam_member`（シークレット単位）、
> Cloud SQL は `google_project_iam_member`（プロジェクト単位）、画像バケットは
> `google_storage_bucket_iam_member`（バケット単位）と、付与先の差がそのままコードに出ている。

## 7. Cloud Storage バケット（frontend / images）

コンソール: **Cloud Storage → バケット → 作成** を2回。どちらも均一アクセス、リージョン asia-northeast1。

- `practice-gcp-stg-frontend`
  - **ウェブサイト設定**: メインページ `index.html` / 404 ページ `index.html`（SPA フォールバック）
  - **公開**: プリンシパル `allUsers` に **Storage オブジェクト閲覧者**
- `practice-gcp-stg-images`
  - **CORS**: オリジン `https://example-gcp.com`、メソッド `GET,HEAD`（仮ドメインは tfvars に合わせる）
  - **公開**: `allUsers` に **Storage オブジェクト閲覧者**

> `gcs.tf`。

## 8. Cloud Run サービス（マルチコンテナ）

コンソール: **Cloud Run → サービスをデプロイ → コンテナイメージから**。

- サービス名: `practice-gcp-stg-web` / リージョン: asia-northeast1
- **Ingress**: 「内部 + Cloud Load Balancing」（= `INTERNAL_LOAD_BALANCING`）
- **未認証の呼び出しを許可**（`allUsers` invoker。LB から到達させるため）
- **コンテナ1（ingress）**: `nginx` イメージ（手順3のリポジトリ + GHA で push したタグ）、**ポート 80**
- **コンテナ2（サイドカー）**: `laravel` イメージ。環境変数を `cloud_run.tf` の `run_env` どおりに設定し、
  シークレット参照（`APP_KEY` / `DB_PASSWORD` / `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`）を「最新」で紐付け
- **接続 → Cloud SQL 接続** に `practice-gcp-stg-mysql` を追加（`/cloudsql/<接続名>` がマウントされる）
- **サービスアカウント**: `practice-gcp-stg-run`
- スケーリング: 最小 0 / 最大 2

> `cloud_run.tf`。`DB_SOCKET` は `/cloudsql/<接続名>` を指す。`<接続名>` は SQL インスタンス詳細で確認。

## 9. Cloud Run ジョブ（migrate）

コンソール: **Cloud Run → ジョブ → ジョブを作成**。

- ジョブ名: `practice-gcp-stg-migrate`
- イメージ: `laravel`、**コマンド** `php` / **引数** `artisan,migrate,--force`
- Cloud SQL 接続・SA・環境変数・シークレットは手順8と同じ
- 実行はコンソールの「実行」ボタン（CLI 不要）

> `cloud_run_job.tf`。

## 10. 外部 HTTPS ロードバランサ + Cloud CDN

コンソール: **ネットワークサービス → ロードバランシング → ロードバランサを作成**
→「アプリケーション ロードバランサ（HTTP/S）」→「グローバル外部」。

事前に **静的 IP**（手順10-1）を確保しておくと URL マップ作成が楽。

1. **静的 IP**: VPC ネットワーク → IP アドレス → グローバル静的 IP を予約: `practice-gcp-stg-lb-ip`
2. **バックエンド**:
   - **バックエンドサービス**（Cloud Run）: 「サーバーレス NEG」を新規作成（`practice-gcp-stg-run-neg`、
     リージョン asia-northeast1、Cloud Run サービス = `practice-gcp-stg-web`）→ バックエンドサービス
     `practice-gcp-stg-run-backend`
   - **バックエンドバケット**（フロント）: `practice-gcp-stg-frontend-backend`、バケット
     `practice-gcp-stg-frontend`、**Cloud CDN 有効**
   - **バックエンドバケット**（画像）: `practice-gcp-stg-images-backend`、バケット
     `practice-gcp-stg-images`、**Cloud CDN 有効**
3. **ルーティング規則（URL マップ `practice-gcp-stg-urlmap`）**:
   - ホスト `example-gcp.com`: パス `/api`, `/api/*` → run-backend、それ以外 → frontend-backend
   - ホスト `img.example-gcp.com`: すべて → images-backend
4. **フロントエンド（HTTPS）**: プロトコル HTTPS / IP=予約した静的 IP / ポート 443 /
   **Google マネージド証明書** `practice-gcp-stg-cert`（ドメイン: `example-gcp.com`, `img.example-gcp.com`）
5. **HTTP→HTTPS リダイレクト**: ポート 80 のフロントエンドを追加し「HTTP を HTTPS にリダイレクト」

> `load_balancer.tf`。証明書はドメインが LB IP を指し DNS 委譲が効くまで `PROVISIONING` のまま。

## 11. Cloud DNS

コンソール: **ネットワークサービス → Cloud DNS → ゾーンを作成**。

- ゾーン名: `practice-gcp-stg-zone` / DNS 名: `example-gcp.com.`（公開ゾーン）
- レコード追加（A）: `example-gcp.com.` と `img.example-gcp.com.` → 値は手順10の静的 IP
- 本番ドメイン取得後、レジストラの NS をこのゾーンの NS に委譲する

> `cloud_dns.tf`。NS は `terraform output dns_name_servers` でも確認可。

## 12. WIF + デプロイ SA（GitHub Actions 用）

コンソール: **IAM と管理 → Workload Identity 連携 → プールを作成**。

1. **プール**: `practice-gcp-stg-gh-pool`
2. **プロバイダ**（OIDC）: `practice-gcp-stg-gh-provider`
   - 発行元 URL: `https://token.actions.githubusercontent.com`
   - 属性マッピング: `google.subject=assertion.sub`, `attribute.repository=assertion.repository`,
     `attribute.ref=assertion.ref`
   - 属性条件: `assertion.repository == '0000masa/react-laravel-practice-public'`
3. **デプロイ SA**（サービスアカウント作成、2つ）:
   - `practice-gcp-stg-push-nginx` → リポジトリ `nginx` に **Artifact Registry 書き込み**
   - `practice-gcp-stg-push-laravel` → リポジトリ `laravel` に **Artifact Registry 書き込み**
4. **WIF 連携の付与**: 各 SA で「アクセスを許可 → Workload Identity ユーザー」を、
   principal セット `principalSet://.../attribute.repository/0000masa/react-laravel-practice-public` に付与

> `ci.tf`。作成・import 後、`terraform output wif_provider` と `gha_push_service_accounts` を
> GitHub Secrets に登録する（[github-actions-image-push.md](./github-actions-image-push.md)）。

---

## import の実行

```sh
cd terraform/gcp/stg
terraform init
# imports.tf の該当ブロックをコメント解除し、<PROJECT_ID> を置換
terraform plan      # 取り込み予定と差分を確認
terraform apply     # state に import + 差分を収束
terraform plan      # 差分ゼロを確認（db_password 等 TF 管理分は apply 後に収束）
```
