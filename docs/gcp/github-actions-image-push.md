# GitHub Actions による Artifact Registry へのイメージ push

イメージのビルド & push **だけ** を GitHub Actions で自動化する（その他のインフラは
[コンソール手動作成 → terraform import](./manual-setup-console.md)）。AWS 版の
`ecr-deploy-nginx.yml` / `ecr-deploy-laravel.yml` の GCP 版にあたる。

## 方針

- **Artifact Registry**（= AWS の ECR 相当）に push する。
- 認証は **Workload Identity Federation（WIF）**。AWS 版の GitHub OIDC ロールと同じく
  **長期キーを GitHub に置かない**パスワードレス方式。
- リポジトリは nginx / laravel で**分割**し、ワークフローも **2 本**に分ける。
  デプロイ SA も分割し、各 SA は**自分のリポジトリにのみ** `artifactregistry.writer`（最小権限）。
- ワークフロー内でも **gcloud CLI を使わない**。`google-github-actions/auth` が出力する
  アクセストークンを `docker/login-action` に渡して docker ログインする。

## ワークフロー

| ファイル | push 先リポジトリ | Dockerfile |
| --- | --- | --- |
| `.github/workflows/gcp-ar-push-nginx.yml` | `nginx` | `docker/ecr/nginx/Dockerfile` |
| `.github/workflows/gcp-ar-push-laravel.yml` | `laravel` | `docker/ecr/backend/Dockerfile` |

- トリガー: `workflow_dispatch`（手動）。AWS 版と同じく好きなタイミングで実行する。
- タグ: `sha-<コミットSHA>`（AWS 版と同じ規約）。

## GitHub Secrets（事前設定）

WIF / デプロイ SA を [コンソールで作成し import](./manual-setup-console.md) した後、
`terraform output` の値を GitHub の Secrets に登録する。

| Secret 名 | 値 | 取得元 |
| --- | --- | --- |
| `GCP_PROJECT_ID` | プロジェクト ID | `terraform.tfvars` の `project_id` |
| `GCP_WIF_PROVIDER` | WIF プロバイダのフルリソース名 | `terraform output wif_provider` |
| `GCP_PUSH_NGINX_SA` | nginx 用 push SA のメール | `terraform output gha_push_service_accounts`（nginx） |
| `GCP_PUSH_LARAVEL_SA` | laravel 用 push SA のメール | `terraform output gha_push_service_accounts`（laravel） |

> `GCP_WIF_PROVIDER` は
> `projects/<NUM>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`
> の形式。

## 流れ

```
GitHub Actions を手動実行
  → WIF でトークン交換（長期キーなし）
  → docker/login-action でアクセストークン認証
  → docker build / push（タグ = sha-<SHA>）
  → terraform.tfvars の image_tag_nginx / image_tag_laravel を当該 SHA に更新
  → terraform apply で Cloud Run の参照イメージを更新
```

## WIF の信頼条件（悪用防止）

`ci.tf` で対象 GitHub リポジトリのトークンだけを受け付ける:

- Provider 側 `attribute_condition`: `assertion.repository == '<owner>/<repo>'`
- SA 側 `workloadIdentityUser`: `principalSet://.../attribute.repository/<owner>/<repo>`

AWS 版が `sub`/`ref` の 2 クレームで branch × environment を絞ったのと同様、
ここでは `attribute.repository` で**対象リポジトリに限定**している（必要なら `attribute.ref`
を足してブランチも絞れる。`attribute_mapping` に `attribute.ref` を用意済み）。
