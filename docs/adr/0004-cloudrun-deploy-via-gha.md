---
status: accepted
---

# Cloud Run のイメージ更新は GitHub Actions で行い、Terraform は image を ignore_changes する

## 背景

当初は「GHA でイメージを push → `terraform.tfvars` の `image_tag_*` を更新 → `terraform apply` で
Cloud Run の参照イメージを更新」というフローだった。AWS 版は push（`ecr-deploy-*`）とコンテナ更新
（`ecs-update-*`）を GitHub Actions で分担しており、GCP もこれに揃えたい。

## 決定

- Cloud Run サービス（`*-web`）とジョブ（`*-migrate`）の**コンテナ image はライブ更新を GitHub Actions が所有**する。
  新規 deploy ワークフロー `gcp-run-deploy-laravel.yml` / `gcp-run-deploy-nginx.yml` が
  **gcloud で対象コンテナの image だけを部分更新**する（`gcloud run services update --container <name> --image`、
  ジョブは `jobs update --image`）。laravel 側は「ジョブ image 更新 → 実行（マイグレーション）→ サービス更新」の順。
- Terraform は **`lifecycle { ignore_changes }` で image だけを無視**する（env / secret / Cloud SQL / SA 等の
  「形」は Terraform 管理のまま）。`tfvars` の `image_tag_*` は**初回作成のシードのみ**に使う。
- deploy 用に **環境別の専用 SA `practice-gcp-${env}-run-deployer`**（`run.developer` を対象サービス/ジョブ単位、
  ランタイム SA への `serviceAccountUser`）を用意し、**GitHub Environments**（`environment: stg|prod`）で
  環境別 secret `GCP_RUN_DEPLOY_SA` と prod 承認ゲートを効かせる。

## 考慮した代替案

- **Cloud Run Admin API を curl + jq で read-modify-write**: 完全に no-gcloud を維持できるが、
  書き戻し時の read-only フィールド除去・revision 名衝突回避を自前で正しく行う必要があり壊れやすい。
  **却下理由**: gcloud の `--container --image` 部分更新が同じことを堅牢にやってくれる。
  - 補足: push ワークフローは `docker/login-action` で完結するため no-gcloud を維持。deploy は gcloud を許容し、
    用途で使い分ける（Cloud Run 更新では gcloud が正攻法）。
- **deploy-cloudrun アクション + full YAML**: マルチコンテナは YAML 必須で、サービスの「形」を GHA が持つことになり
  Terraform 管理（ignore は image だけ）と二重所有で衝突する。**却下理由**: 部分更新と相性が悪い。
- **gcloud run services replace（YAML を取得→image 差し替え→replace）**: 可能だが、`--container --image` の
  部分更新で十分かつ簡潔。

## トレードオフ / 影響

- **image は Terraform の管理外**になる。`terraform plan` はライブの実イメージを追跡せず、コード（state）から
  「今動いているイメージ」は分からない。再現性の一部を GHA に委ねる。
- **`tfvars` の `image_tag_*` を変えても再デプロイされない**（ignore されるため）。**ライブ更新の唯一の経路は
  deploy ワークフロー**になる。`image_tag_*` は初回 apply 前に push 済み sha を入れる bootstrap シード。
- `ignore_changes` の index はコンテナ記述順に依存（web: 0=nginx / 1=laravel、job: 0=laravel）。順序変更に注意。
- prod は未構築。同名規約（`practice-gcp-prod-*`）で prod インフラを建てれば、同じワークフローで `target_env=prod` が動く。
