# GitHub Actions による Artifact Registry push と Cloud Run デプロイ

イメージの **ビルド & push** と、push 済みイメージでの **Cloud Run 更新（デプロイ）** を
GitHub Actions で行う。その他のインフラは
[コンソール手動作成 → terraform import](./manual-setup-console.md)。AWS 版の
`ecr-deploy-*.yml`（push）/ `ecs-update-*.yml`（更新）の GCP 版にあたる。

## 全体像（push と deploy の役割分担）

```
[push]   gcp-ar-push-{nginx,laravel}.yml
           → WIF で push SA を impersonate → docker build/push（タグ sha-<SHA>）→ Artifact Registry

[deploy] gcp-run-deploy-{nginx,laravel}.yml
           → WIF で deploy SA を impersonate → gcloud で Cloud Run のコンテナ image を部分更新
           → laravel は「migrate ジョブ更新 → 実行 → サービス更新」の順
```

- **push は環境非依存**（単一の Artifact Registry に sha タグで積むだけ。AWS の ECR push と同じ）。
- **deploy は環境別**（`target_env` = stg / prod。GitHub Environments で環境別 secret と prod 承認）。
- ドメインと Artifact Registry は stg/prod で**共有**（同一 GCP プロジェクト。[CONTEXT.md](../../CONTEXT.md) の「環境」）。

> **重要な前提**: Cloud Run のライブイメージは **deploy ワークフローが所有**する。Terraform は
> サービス/ジョブの image を `ignore_changes` しており、`terraform apply` では更新されない
> （[ADR 0004](../adr/0004-cloudrun-deploy-via-gha.md)）。**ライブ更新の唯一の経路は deploy ワークフロー**。

## ワークフロー一覧

| ファイル | 種別 | 対象 | 入力 |
| --- | --- | --- | --- |
| `gcp-ar-push-nginx.yml` | push | AR リポジトリ `nginx`（Dockerfile `docker/ecr/nginx/Dockerfile`） | なし（タグ = `sha-<SHA>`） |
| `gcp-ar-push-laravel.yml` | push | AR リポジトリ `laravel`（Dockerfile `docker/ecr/backend/Dockerfile`） | なし（タグ = `sha-<SHA>`） |
| `gcp-run-deploy-nginx.yml` | deploy | サービス `practice-gcp-${env}-web` の **nginx** コンテナ | `IMAGE_TAG_NGINX`（必須）, `target_env` |
| `gcp-run-deploy-laravel.yml` | deploy | migrate ジョブ実行 + サービスの **laravel** コンテナ | `IMAGE_TAG_LARAVEL`（必須）, `target_env` |

- トリガーはすべて `workflow_dispatch`（手動）。
- 認証は **Workload Identity Federation（WIF）**。長期キーを GitHub に置かないパスワードレス方式（AWS の GitHub OIDC 相当）。
- **push は gcloud を使わない**（`docker/login-action` にアクセストークンを渡す）。
  **deploy は gcloud を使う**（`gcloud run services update --container --image` の部分更新が堅牢なため。
  使い分けの理由は後述「設計判断」）。

## 必要な GCP 側の設定

| リソース | 作り方 | 補足 |
| --- | --- | --- |
| Artifact Registry `nginx` / `laravel` | **コンソールで作成（Terraform 非管理・data 参照）** | 最初の `terraform plan` より前に存在必須。**Immutable image tags を有効化**。[手順3](./manual-setup-console.md) / [ADR 0003](../adr/0003-artifact-registry-unmanaged.md) |
| WIF プール / プロバイダ | コンソール作成 → import | [手順12](./manual-setup-console.md) |
| push SA `*-push-nginx` / `*-push-laravel` | コンソール作成 → import | 各々自分の AR リポジトリにのみ `artifactregistry.writer`（最小権限） |
| deploy SA `*-run-deployer` | **Terraform 管理（`ci.tf`）** | `run.developer`（対象サービス/ジョブ単位）+ ランタイム SA への `serviceAccountUser`。環境別 |

## GitHub Secrets

WIF / SA を作成・import・apply した後、`terraform output` の値を GitHub に登録する。

### リポジトリ共通（Settings → Secrets and variables → Actions）

| Secret 名 | 値 | 取得元 |
| --- | --- | --- |
| `GCP_PROJECT_ID` | プロジェクト ID | `terraform.tfvars` の `project_id` |
| `GCP_WIF_PROVIDER` | WIF プロバイダのフルリソース名 | `terraform output wif_provider` |
| `GCP_PUSH_NGINX_SA` | nginx 用 push SA のメール | `terraform output gha_push_service_accounts`（nginx） |
| `GCP_PUSH_LARAVEL_SA` | laravel 用 push SA のメール | `terraform output gha_push_service_accounts`（laravel） |

> `GCP_PROJECT_ID` / `GCP_WIF_PROVIDER` は stg/prod 共通（同一プロジェクト・同一 WIF プール）。

### 環境別（Settings → Environments → `stg` / `prod` を作成し、その中の Secrets に設定）

| Secret 名 | 値 | 取得元 |
| --- | --- | --- |
| `GCP_RUN_DEPLOY_SA` | その環境の deploy SA メール | `terraform output run_deploy_service_account` |

> deploy ワークフローは `environment: ${{ inputs.target_env }}` を指定しており、`target_env` で選んだ
> 環境（`stg` / `prod`）の secret が使われる。**prod 環境に必須レビュー（承認）を設定**すれば、prod デプロイに
> 承認ゲートがかかる（AWS の `environment:` と同型）。

## 一気通貫の手順（ゼロ → デプロイ）

```
0. Artifact Registry を作成（コンソール、Immutable tags 有効）         ← terraform より前に必須
1. WIF / push SA を作成 → import（手順12）、terraform apply
   （apply で deploy SA = *-run-deployer も作成される）
2. terraform output → リポジトリ共通 Secrets を登録
3. GitHub Environments(stg/prod) を作成 → GCP_RUN_DEPLOY_SA を環境別に登録（prod は承認ルールも）
4. push ワークフロー（gcp-ar-push-*）を手動実行 → AR に sha-<SHA> で push
5. bootstrap: tfvars の image_tag_{nginx,laravel} に手順4の sha を設定 → terraform apply
   （Cloud Run サービス/ジョブが、その sha イメージで初回作成される）
6. 以降のデプロイ: deploy ワークフロー（gcp-run-deploy-*）に sha タグと target_env を渡して実行
   （terraform は触らない。サービス/ジョブの image は ignore_changes 済み）
```

> **`sha-<SHA>` のイミュータブル運用**: タグは sha 固定で `latest` のような移動タグは使わない。AR の
> Immutable tags を有効にしているため、同一コミットでの push 再実行は**2回目が失敗**する（上書き不可。
> 再ビルドしたいなら新コミット）。これは不変性の狙いどおり。

## 設計判断・代替案

### なぜ deploy を GHA にし、Terraform は image を ignore_changes するのか
[ADR 0004](../adr/0004-cloudrun-deploy-via-gha.md)。AWS の push/更新 分担に揃え、デプロイを速く・
承認付きで回すため。代償として「今動いているイメージ」は Terraform から追跡できなくなる。

### なぜ Cloud Run の更新は gcloud を使うのか（push は使わないのに）
マルチコンテナ（nginx + laravel）の Cloud Run は、`gcloud run services update --container <name> --image`
で**対象コンテナの image だけを部分更新**でき、他コンテナ・env・secret・Cloud SQL 接続を保持する。
push 側は `docker/login-action` で完結するため gcloud 不要だが、Cloud Run 更新では gcloud が正攻法。
**用途で使い分ける**。

### 代替案: Cloud Run Admin API を curl + jq で read-modify-write（不採用）

**どういう方法か**: deploy も gcloud を使わず、**Cloud Run Admin API を curl で直接叩く**やり方。
WIF で得たアクセストークンで、

1. `GET https://run.googleapis.com/v2/projects/<PID>/locations/<region>/services/<svc>` で現在のサービス定義（JSON）を取得（read）
2. `jq` で対象コンテナの `.image` だけ差し替え、新リビジョン名衝突を避けるため `.template.revision` を消す（modify）
3. `PATCH .../services/<svc>?updateMask=template` で書き戻す（write）

AWS の `ecs-update-laravel.yml`（タスク定義を describe → image を render → deploy）と同じ「read-modify-write」型。

**今回なぜ使わなかったか**: 書き戻し時に**読み取り専用フィールドの除去**や**リビジョン名衝突の回避**を自前で
正しく行う必要があり、壊れやすい。gcloud の `--container --image` 部分更新が**同じこと（現状を読んで image だけ
替えて書き戻す）を堅牢に**やってくれるため、わざわざ手組みする利点が無い（push と違い deploy は gcloud が自然）。

**なぜ一般に（curl で手叩きが）使われないか**: Cloud Run Admin API は**ツールが内部で呼ぶための土台**であり、
人が curl で routine に叩くことを主目的に設計されていない。read-modify-write・認証・リトライ・フィールドマスク・
リビジョン管理といった煩雑さを、gcloud / 公式アクション / Terraform プロバイダ / クライアントライブラリが
肩代わりするので、通常はそれらを使う。手叩きは「gcloud が使えない環境」「独自コントローラを書く」等の特殊事情向け。

**Cloud Run Admin API とは本来何か**: Cloud Run のリソース（サービス / リビジョン / ジョブ / 実行）を管理する
**REST API 本体**。gcloud、Cloud Console、Terraform プロバイダ、各言語のクライアントライブラリは**すべてこの API を
内部で呼んでいる**。想定用途は「ツールや IaC・CI からのプログラム的な管理・自動化」であり、その上位ラッパー
（gcloud 等）を使うのが通常の運用。

## WIF の信頼条件（悪用防止）

`ci.tf` で対象 GitHub リポジトリのトークンだけを受け付ける（push SA・deploy SA とも同じ仕組み）:

- Provider 側 `attribute_condition`: `assertion.repository == '<owner>/<repo>'`
- SA 側 `workloadIdentityUser`: `principalSet://.../attribute.repository/<owner>/<repo>`

AWS 版が `sub`/`ref` の 2 クレームで branch × environment を絞ったのと同様、ここでは `attribute.repository`
で**対象リポジトリに限定**している（必要なら `attribute.ref` を足してブランチも絞れる。`attribute_mapping` に
`attribute.ref` を用意済み）。
