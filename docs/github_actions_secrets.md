# GitHub Actions 用 IAM ロール ARN シークレット一覧

`.github/workflows/` 配下の各ワークフローは、AWS リソースへアクセスするために GitHub OIDC を介して用途別の IAM ロールを AssumeRole する。本ドキュメントは GitHub の Settings → Secrets and variables → Actions に登録する **シークレット名** と、対応する **IAM ロール ARN** を環境ごとに整理したものである。

実体のロールは Terraform 側 `modules/app-infrastructure/iam_github_actions.tf` で定義され、`output "github_actions_role_arns"` から ARN を取り出せる。Terraform apply 後に出力された値で、本ドキュメントのプレースホルダ ARN を実際の値に置き換えること。

---

## 1. アカウント ID プレースホルダ

本ドキュメントの ARN 例で使用するアカウント ID はあくまでプレースホルダ（仮の値）であり、実際のアカウント ID で置き換える必要がある。

| 環境 | プレースホルダ アカウント ID | 備考 |
| --- | --- | --- |
| stg  | `111111111111` | ステージング環境用 AWS アカウント |
| prod | `222222222222` | 本番環境用 AWS アカウント |

---

## 2. ロールの trust policy 制約

| ロール種別 | sub クレーム (StringEquals / StringLike) | 追加 condition (StringEquals) | 引き受けの条件 |
| --- | --- | --- | --- |
| ECR push (Laravel / Nginx) | `repo:0000masa/react-laravel-practice:*` (StringLike) | なし | 任意 ref / environment（修正ブランチで stg 確認するため） |
| 環境別 7 種 (stg) | `repo:0000masa/react-laravel-practice:environment:stg` | `token.actions.githubusercontent.com:ref` = `refs/heads/main` | stg environment + main ブランチ |
| 環境別 7 種 (prod) | `repo:0000masa/react-laravel-practice:environment:prod` | `token.actions.githubusercontent.com:ref` = `refs/heads/main` | prod environment + main ブランチ |

環境別 7 ロールは「`environment:` を `stg`／`prod` に指定したジョブ」かつ「`main` ブランチからの起動」の **両方** を満たさないと AssumeRole に失敗する。`main` 以外のブランチから `workflow_dispatch` で動かそうとした場合、`Configure AWS Credentials` ステップで止まる。

> モジュール側 (`enable_github_oidc = true`) が自動付与する condition: `iss` の `ForAllValues:StringEquals`、`aud` = `sts.amazonaws.com`、`sub` の StringEquals/StringLike。`ref` 制約だけ `trust_policy_conditions` で追加している（`terraform/modules/app-infrastructure/iam_github_actions.tf` 内の `trust_conditions_main_only` を参照）。

---

## 2-A. 補足: なぜ `sub` だけで environment + branch を同時に縛れないのか

### `sub` クレームのフォーマット仕様

GitHub Actions OIDC トークンの `sub` クレームは、**ジョブが `environment:` を指定しているかどうかで形式が変わる**:

| ジョブの状態 | `sub` の形式 |
| --- | --- |
| `environment:` 指定なし | `repo:OWNER/REPO:ref:refs/heads/BRANCH` |
| `environment:` 指定あり | `repo:OWNER/REPO:environment:NAME` |

両形式が同時に `sub` に入ることはない。つまり trust policy で `:sub` だけを `StringEquals` していると、

- **「environment は stg かつ main ブランチ」** のような AND 条件
- **「main ブランチかつ environment が stg」** のように両方を `sub` 内で同時に強制すること

ができない。

### 解決策: 別クレームを併用する

OIDC トークンには `sub` 以外にも以下のような独立したクレームがあり、IAM trust policy の condition は **複数並べると AND として評価される**。

| クレーム | 略の由来 / 正式名 | 内容 | 例 |
| --- | --- | --- | --- |
| `token.actions.githubusercontent.com:sub` | **sub**ject（JWT 標準クレーム / RFC 7519 §4.1.2）<br>= 「このトークンが誰／何に関するものか」を表す主体の識別子 | GitHub OIDC ではリポジトリ・ref・environment 等を組み合わせた合成文字列 | `repo:OWNER/REPO:environment:stg` |
| `token.actions.githubusercontent.com:ref` | **ref**erence（Git ref）<br>= Git のブランチ／タグ参照名 | ジョブを起動した Git ref | `refs/heads/main` |
| `token.actions.githubusercontent.com:repository` | （略なし。そのまま "repository"） | リポジトリ名 | `OWNER/REPO` |
| `token.actions.githubusercontent.com:repository_owner` | （略なし。そのまま "repository owner"） | オーナー名 | `OWNER` |
| `token.actions.githubusercontent.com:workflow_ref` | workflow + **ref**erence | ワークフローファイルの ref | `OWNER/REPO/.github/workflows/db-task.yml@refs/heads/main` |
| `token.actions.githubusercontent.com:job_workflow_ref` | job + workflow + **ref**erence | reusable workflow の場合の起点 | （reusable のみ） |
| `token.actions.githubusercontent.com:environment` | （略なし。そのまま "environment"） | environment 名（指定時のみ） | `stg` |

> 補足: `Condition` ブロックに登場する他の JWT 標準クレームも RFC 7519 由来の略語: **`aud` = audience**（このトークンを誰向けに発行したか / §4.1.3）、**`iss` = issuer**（発行者 / §4.1.1）、**`exp` = expiration time**、**`iat` = issued at**、**`nbf` = not before**、**`jti` = JWT ID**。本リポの trust policy では `aud`（`sts.amazonaws.com`）と `iss`（`https://token.actions.githubusercontent.com`）をモジュールが自動付与している。

クレーム一覧の出典は GitHub Docs の「Security hardening your deployments / About security hardening with OpenID Connect」を参照。

### 本リポでの実装

- `enable_github_oidc = true` でモジュールが `sub` / `aud` / `iss` を自動付与
- `trust_policy_conditions` で `:ref` = `refs/heads/main` を追加
- 結果として「environment:NAME と一致する `sub`」**かつ**「`refs/heads/main` の `ref`」の **2 クレーム併用** で environment と branch を同時に強制

ECR push 系 2 ロールは、修正ブランチからの ECR push を許容したいので `oidc_wildcard_subjects` で `:*` だけ、`ref` 制約は付けていない。

---

## 2-B. GitHub Environment のブランチ保護ルールとは

GitHub の `Settings → Environments → [env 名]` 画面で設定する、**特定 environment へデプロイ可能な ref を絞り込む機能**。Environment は GitHub Actions のジョブが `environment:` で参照する単位で、本リポでは `stg` と `prod` を想定。

主な設定項目:

| 設定項目 | 内容 |
| --- | --- |
| **Deployment branches and tags** | この environment へ deploy できる ref を制限。`No restriction` / `Protected branches only` / `Selected branches and tags` から選択 |
| **Required reviewers** | この environment に進む前に承認者のレビューを必須にする（最大 6 人） |
| **Wait timer** | デプロイ実行前の待機時間（分）。承認後でも一定時間ロールバック猶予を取れる |
| **Allow administrators to bypass configured protection rules** | 管理者が保護ルールをバイパス可能にするか |

### 例: `Deployment branches and tags` を `Selected branches and tags` で `main` のみ許可

別ブランチから `workflow_dispatch` で `target_env=stg` を指定して動かそうとしても、GitHub 側で

```
Branch <branch-name> is not allowed to deploy to stg due to environment protection rules.
```

と弾かれ、ジョブは起動すらしない。

### 本リポでの位置づけ

IAM trust policy 側で既に `ref = refs/heads/main` を強制しているので **必須ではない**が、**defense-in-depth として併用するのが推奨**。多層化することで:

- IAM 設定ミスで `ref` 条件が外れた場合でも GitHub 側で止められる
- `Required reviewers` を付けることで prod デプロイに人の承認を入れられる（IAM だけでは表現できない）
- `Wait timer` でロールバック猶予を取れる

特に **prod environment は `main` のみ許可 + Required reviewers 必須** に設定するのを推奨する。

---

## 2-C. 補足: Condition 演算子 `StringEquals` と `ForAllValues:StringEquals`

trust policy のうち、`Condition` ブロックの中に `StringEquals` と `ForAllValues:StringEquals` の **2 種類の演算子** が並んでいる。本セクションではこの違いと、なぜ使い分けているかを整理する。

### 実際の trust policy（例: stg の migrate ロール）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GithubOidcAuth",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": ["sts:TagSession", "sts:AssumeRoleWithWebIdentity"],
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:ref": "refs/heads/main",
          "token.actions.githubusercontent.com:sub": "repo:0000masa/react-laravel-practice:environment:stg"
        },
        "ForAllValues:StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:iss": "https://token.actions.githubusercontent.com"
        }
      }
    }
  ]
}
```

### `StringEquals`（単一値オペレーター）

- リクエストコンテキスト（= JWT クレーム）の **値が単一の文字列** であることを前提に判定
- ポリシー側の許可リストの **いずれかと完全一致** すれば true
- リクエスト側にキーが存在しない（値が空）場合は **false**
- `sub` / `ref` は GitHub OIDC が必ず単一文字列で発行するクレームなので `StringEquals` を使う。**欠落した不正トークンを確実に拒否できる**のがポイント

### `ForAllValues:StringEquals`（集合演算子）

公式定義 (AWS Docs):

> Tests whether the value of every member of the request set is a subset of the condition key set.

要するに「**JWT 側のキーに紐づく値（複数あり得る）が全部、ポリシー側の許可セットの中に含まれていれば true**」という判定。

- `aud` / `iss` のように **JWT 仕様（RFC 7519）で配列も許される**クレームに対して、配列で来ても単一値で来ても安全に評価できるようにするための演算子
- IAM の用語ではこれを **multi-valued context key**（複数値を持ち得る condition key）と呼ぶ。「キー名そのものが配列」ではなく、「**1 つのキーに紐づく値が複数あり得る**」という意味

### ⚠️ `ForAllValues` の罠: キーが空なら true（vacuously true）

`ForAllValues:StringEquals` は **「リクエスト側にキーが無い／値ゼロ」の場合に vacuously true** を返す仕様（空集合は任意の集合のサブセット、という数学的定義から）。

これを `sub` のような認証クリティカルなクレームに使うと、`sub` が欠落した不正トークンが**素通りする**リスクがある（実際 AWS は 2023 年にこのアンチパターンに対するセキュリティ警告を出している）。

そのため:

| クレーム | 演算子 | 理由 |
| --- | --- | --- |
| `sub` / `ref` | `StringEquals` | 単一値で必須。欠落で fail させたい |
| `aud` / `iss` | `ForAllValues:StringEquals` | 配列の可能性があり、内容が許可セット内であることを保証したい |

これが本リポの trust policy が 2 種類の演算子を使い分けている理由。

### `ForAllValues:StringEquals` ブロックの書き方バリエーション（JSON）

#### 1. キー 1 つ・許可値 1 つ

```json
"ForAllValues:StringEquals": {
  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
}
```

#### 2. キー 1 つ・許可値が配列（複数の許容値）

```json
"ForAllValues:StringEquals": {
  "token.actions.githubusercontent.com:aud": [
    "sts.amazonaws.com",
    "another-aud-value"
  ]
}
```

→ JWT 側の `aud` の **すべての値** が `{"sts.amazonaws.com", "another-aud-value"}` の **サブセット** ならOK。

| トークン側 `aud` | 結果 |
| --- | --- |
| `"sts.amazonaws.com"` | ✅ |
| `["sts.amazonaws.com"]` | ✅ |
| `["sts.amazonaws.com", "another-aud-value"]` | ✅ |
| `["sts.amazonaws.com", "evil.example.com"]` | ❌ (`evil.example.com` が許可セット外) |

#### 3. 複数のキーを同じブロックにまとめる（**現状の実装**）

```json
"ForAllValues:StringEquals": {
  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
  "token.actions.githubusercontent.com:iss": "https://token.actions.githubusercontent.com"
}
```

→ 同じブロック内のキー同士は **AND** で評価される。

#### 4. 異なる演算子のブロックを `Condition` 直下に並列に置く（**現状の実装**）

```json
"Condition": {
  "ForAllValues:StringEquals": { /* ... */ },
  "StringEquals": { /* ... */ }
}
```

→ `Condition` 直下の演算子ブロック同士も **AND** で評価される。

### Terraform から書く場合（`aws_iam_policy_document`）

`terraform-aws-modules/iam/aws//modules/iam-role` モジュールの `trust_policy_conditions` や、生の `aws_iam_policy_document` data source は、`condition` ブロックを次の **3 属性 (`test`, `variable`, `values`)** の固定キーで表現する。

```hcl
trust_policy_conditions = [
  {
    test     = "ForAllValues:StringEquals"
    variable = "token.actions.githubusercontent.com:repository_owner"
    values   = ["0000masa"]
  }
]
```

| 属性 | 対応する IAM JSON 上の概念 | 例 |
| --- | --- | --- |
| `test` | Condition Operator（演算子名） | `"StringEquals"`、`"ForAllValues:StringEquals"`、`"StringLike"`、`"NumericLessThan"` 等 |
| `variable` | Condition Key（条件キーの識別子） | `"token.actions.githubusercontent.com:sub"`、`"aws:SourceIp"` 等 |
| `values` | 許可される値のリスト | `["repo:.../environment:stg"]` |

#### なぜ `test` という属性名なのか

AWS の公式 IAM ドキュメントでは「**Condition operator**（条件演算子）」と呼ばれているが、Terraform 側はこれを `test` と命名している。理由は次のとおり推測できる:

1. **「ポリシー評価＝条件をテスト（assertion）する行為」というメンタルモデル** — IAM 評価ロジックでは各 condition は「リクエストコンテキストを test する式」として扱われる。「`StringEquals` という test を `aws:PrincipalOrgID` に対してかける」と読めば自然
2. **`operator` という名前を避けた** — HCL の世界で `operator` は別の意味を持ち得る（演算子記号や言語仕様）ので中立的な `test` を採用したと思われる
3. **後方互換** — `aws_iam_policy_document` は AWS provider 初期から存在し、HashiCorp はリソース属性の rename を基本しないため長年そのまま定着している

要は「`test` は Terraform AWS provider が決めた固定の属性名で、『この演算子で条件を判定する』ことを表す名前」と覚えておけばよい。

---

## 3. シークレット登録先と命名規則

- **登録先**: GitHub リポジトリの `Settings` → `Environments` → `stg` / `prod` の各 environment に **Environment secrets** として登録する。
- **環境固定 (environment 指定なし) のワークフロー**: `ecr-deploy-laravel.yml` / `ecr-deploy-nginx.yml` のみ。これらは Repository secrets として登録する（stg/prod の環境分離を行わない）。
- **命名規則**: `AWS_<用途>_ROLE_ARN`

---

## 4. ECR push 系 (Repository secrets)

任意 ref から実行可能、environment 指定なし。**Repository secrets** に登録する。

| シークレット名 | 用途（使用ワークフロー） | Terraform リソース | ARN（プレースホルダ） |
| --- | --- | --- | --- |
| `AWS_ECR_LARAVEL_ROLE_ARN` | `ecr-deploy-laravel.yml`<br>Laravel イメージを ECR に push | `module.gha_ecr_laravel_role`<br>(`practice-stg-gha-ecr-laravel-role` 等) | `arn:aws:iam::111111111111:role/practice-stg-gha-ecr-laravel-role` |
| `AWS_ECR_NGINX_ROLE_ARN`   | `ecr-deploy-nginx.yml`<br>Nginx イメージを ECR に push    | `module.gha_ecr_nginx_role`<br>(`practice-stg-gha-ecr-nginx-role` 等)   | `arn:aws:iam::111111111111:role/practice-stg-gha-ecr-nginx-role`   |

> **Note**: ECR push 系も将来的に prod 用 ECR を別アカウントに分離するなら environment 化が必要になるが、現状は単一アカウントの単一 ECR を共有する想定のため Repository secrets に置く。

---

## 5. stg environment secrets

ECR push 以外の **6 ワークフロー** が `environment: ${{ inputs.target_env }}` で参照する。`target_env=stg` を選択した時のみこちらの値が解決される。各ロールの trust policy は **`sub` = `repo:0000masa/react-laravel-practice:environment:stg`** かつ **`ref` = `refs/heads/main`** を要求するため、stg environment かつ main ブランチからのジョブだけが AssumeRole できる。

| シークレット名 | 用途（使用ワークフロー） | Terraform リソース | ARN（プレースホルダ） |
| --- | --- | --- | --- |
| `AWS_ECS_UPDATE_LARAVEL_ROLE_ARN`       | `ecs-update-laravel.yml`<br>main service の Laravel コンテナ更新       | `module.gha_ecs_update_laravel_role` | `arn:aws:iam::111111111111:role/practice-stg-gha-ecs-update-laravel-role` |
| `AWS_ECS_UPDATE_NGINX_ROLE_ARN`         | `ecs-update-nginx.yml`<br>main service の Nginx コンテナ更新           | `module.gha_ecs_update_nginx_role`   | `arn:aws:iam::111111111111:role/practice-stg-gha-ecs-update-nginx-role`   |
| `AWS_ECS_UPDATE_LARAVEL_QUEUE_ROLE_ARN` | `ecs-update-laravel-que.yml`<br>queue worker サービスの更新            | `module.gha_ecs_update_queue_role`   | `arn:aws:iam::111111111111:role/practice-stg-gha-ecs-update-laravel-queue-role` |
| `AWS_DB_RUNNER_ROLE_ARN`                | `db-task.yml`<br>runner タスクで migrate / seed / shell を run-task    | `module.gha_db_runner_role`          | `arn:aws:iam::111111111111:role/practice-stg-gha-db-runner-role`          |
| `AWS_S3_DEPLOY_FRONTEND_ROLE_ARN`       | `s3-deploy-frontend.yml`<br>フロントエンド S3 同期と CloudFront 失効化 | `module.gha_s3_deploy_frontend_role` | `arn:aws:iam::111111111111:role/practice-stg-gha-s3-deploy-frontend-role` |
| `AWS_ECSPRESSO_ROLE_ARN`                | `ecspresso-update-task.yml`<br>ecspresso によるタスク定義登録／デプロイ | `module.gha_ecspresso_role`          | `arn:aws:iam::111111111111:role/practice-stg-gha-ecspresso-role`          |

---

## 6. prod environment secrets

ECR push 以外の **6 ワークフロー** が `target_env=prod` を選択した時に参照する。prod 環境用の Terraform (`terraform/prod/`) は別途作成予定で、`github_environment_name = "prod"` を `terraform.tfvars` に設定する。各ロールの trust policy は **`sub` = `repo:0000masa/react-laravel-practice:environment:prod`** かつ **`ref` = `refs/heads/main`** を要求する。アカウント ID とロール名はプレースホルダ。

| シークレット名 | Terraform リソース | ARN（プレースホルダ） |
| --- | --- | --- |
| `AWS_ECS_UPDATE_LARAVEL_ROLE_ARN`       | `module.gha_ecs_update_laravel_role` | `arn:aws:iam::222222222222:role/practice-prod-gha-ecs-update-laravel-role` |
| `AWS_ECS_UPDATE_NGINX_ROLE_ARN`         | `module.gha_ecs_update_nginx_role`   | `arn:aws:iam::222222222222:role/practice-prod-gha-ecs-update-nginx-role`   |
| `AWS_ECS_UPDATE_LARAVEL_QUEUE_ROLE_ARN` | `module.gha_ecs_update_queue_role`   | `arn:aws:iam::222222222222:role/practice-prod-gha-ecs-update-laravel-queue-role` |
| `AWS_DB_RUNNER_ROLE_ARN`                | `module.gha_db_runner_role`          | `arn:aws:iam::222222222222:role/practice-prod-gha-db-runner-role`          |
| `AWS_S3_DEPLOY_FRONTEND_ROLE_ARN`       | `module.gha_s3_deploy_frontend_role` | `arn:aws:iam::222222222222:role/practice-prod-gha-s3-deploy-frontend-role` |
| `AWS_ECSPRESSO_ROLE_ARN`                | `module.gha_ecspresso_role`          | `arn:aws:iam::222222222222:role/practice-prod-gha-ecspresso-role`          |

> stg と prod は **同じシークレット名** を使う。GitHub Actions 上では environment が切り替わるたびに secret も自動的に対応する environment のものに解決される。シークレット値（=ロール ARN）の指す先のロールは environment ごとに分離されており、trust policy の `sub` も `environment:stg` / `environment:prod` で別々に縛られている。

---

## 7. Terraform 側で対象外のワークフロー

以下 2 本は Terraform リソース管理用の専用ロールを使い続ける。本ドキュメントのスコープ外である。

| ワークフロー | 使用シークレット | 役割 |
| --- | --- | --- |
| `terraform-apply-plan.yml`  | `AWS_TERRAFORM_ROLE_ARN` | Terraform の plan / apply（environment は input で stg/prod を切り替え済み） |
| `terraform-destroy-stg.yml` | `AWS_TERRAFORM_ROLE_ARN` | stg 環境向け `terraform destroy`                                         |

---

## 8. シークレット登録手順

### 8-1. Environment secrets（stg / prod）

1. GitHub リポジトリで `Settings` → `Environments` を開く。
2. `stg`（および `prod`）の environment が無ければ新規作成する。
3. Environment 詳細画面の `Environment secrets` で `Add secret` をクリック。
4. シークレット名（例: `AWS_DB_RUNNER_ROLE_ARN`）と、対応する環境の ARN（例: `arn:aws:iam::<実 stg アカウント ID>:role/practice-stg-gha-db-runner-role`）を入力して保存。
5. 上の §5 / §6 の表に記載された 6 種類すべてを stg / prod それぞれに登録する。

### 8-2. Repository secrets（ECR push 系）

1. `Settings` → `Secrets and variables` → `Actions` → `Repository secrets` の `New repository secret` をクリック。
2. `AWS_ECR_LARAVEL_ROLE_ARN`、`AWS_ECR_NGINX_ROLE_ARN` の 2 つを登録する。

### 8-3. Terraform output からの取り出し例

```bash
cd stg
terraform output -json github_actions_role_arns | jq
```

出力例（プレースホルダ）:

```json
{
  "ecr_laravel":        "arn:aws:iam::111111111111:role/practice-stg-gha-ecr-laravel-role",
  "ecr_nginx":          "arn:aws:iam::111111111111:role/practice-stg-gha-ecr-nginx-role",
  "ecs_update_laravel": "arn:aws:iam::111111111111:role/practice-stg-gha-ecs-update-laravel-role",
  "ecs_update_nginx":   "arn:aws:iam::111111111111:role/practice-stg-gha-ecs-update-nginx-role",
  "ecs_update_queue":   "arn:aws:iam::111111111111:role/practice-stg-gha-ecs-update-laravel-queue-role",
  "db_runner":          "arn:aws:iam::111111111111:role/practice-stg-gha-db-runner-role",
  "s3_deploy_frontend": "arn:aws:iam::111111111111:role/practice-stg-gha-s3-deploy-frontend-role",
  "ecspresso":          "arn:aws:iam::111111111111:role/practice-stg-gha-ecspresso-role"
}
```

ここから対応するシークレット名へマッピングして登録する。

---

## 9. GitHub Actions 用 IAM ロールを Terraform で管理することの是非

本リポでは Terraform 実行用ロール (`AWS_TERRAFORM_ROLE_ARN`) のみを手動で作成し、それ以外の 9 種類の GitHub Actions 用ロールは Terraform (`modules/app-infrastructure/iam_github_actions.tf`) で管理している。これはベストプラクティスか？という疑問に答える。

### 結論

**現状の構成（Terraform 実行ロールのみ手動 + その他は Terraform 管理）は一般的に推奨されるベストプラクティスである。** GitHub Actions OIDC ロールは Terraform で管理するのが望ましい。ただし、必ず 1 つだけ「Terraform 自身を実行するためのロール」は手動 (or 別 bootstrap) で先に作る必要がある（ブートストラップ問題）。

### Terraform 管理が望ましい理由

| 観点 | 説明 |
| --- | --- |
| **IaC として一貫性が保てる** | 信頼ポリシー（OIDC sub クレーム条件）や付与する `iam:Policy` の中身がコードに残り、PR レビューと git history で追跡できる。誰がいつ権限を増減させたかが追える。 |
| **環境ごとの再現性** | stg / prod を `var.project_name` の差し替えだけで同等構成にできる。手動だと環境差異が必ず出る。 |
| **ドリフト検知** | コンソールでの直接編集を `terraform plan` で検出できる。 |
| **最小権限の可視化** | `iam_policy_github_actions.tf` のような形でポリシー JSON が並ぶため、過剰権限のレビューがしやすい。 |
| **モジュールの再利用** | `terraform-aws-modules/iam/aws//modules/iam-role` のようなコミュニティモジュールを使えば、信頼ポリシーや OIDC 条件を共通化できる。 |

### ブートストラップ問題（Terraform 実行ロールだけは手動）

OIDC でロールを引き受けるための IAM ロールを Terraform で作るには、**Terraform を実行するためのロールが先に存在している** 必要がある。鶏が先か卵が先かになるため、最低 1 つは手動で作る必要がある。

本リポでは `terraform-apply-plan.yml` / `terraform-destroy-stg.yml` が参照する `AWS_TERRAFORM_ROLE_ARN` がこれにあたり、コンソール（または別の bootstrap 用ミニ Terraform）で作成している。これは設計上正しい。

### Terraform 管理のリスクと緩和策

| リスク | 緩和策 |
| --- | --- |
| Terraform 実行ロールが侵害されると、攻撃者が任意の IAM ロール／ポリシーを作成できてしまう | Terraform 実行ロールには `iam:*` を全リソースに対して付与せず、`Resource` でロール名プレフィックス（例: `arn:aws:iam::*:role/practice-*-gha-*`）に限定する。 |
| `terraform destroy` で CI/CD 用ロールが消失し、デプロイ系ワークフローが全停止する | 本番環境で破壊しては困るロールには `lifecycle { prevent_destroy = true }` を付ける。または IAM のみ state を分離する。 |
| 信頼ポリシーや OIDC sub 条件を誤編集すると、AssumeRole が一切通らなくなる | trust policy の変更は必ず PR レビュー必須。緊急時に備え、手動でも引き受け可能な復旧用ロールを別途用意しておくと安全。 |
| Terraform 実行ロール自身を Terraform 構成で書き換えると、壊れた瞬間に Terraform を回せず復旧不能になる | Terraform 実行ロールは **対象の Terraform 構成の外** で管理する（本リポはこのパターン）。 |

### 「手動で作る」方が望ましいケース

以下の状況では Terraform 化のメリットがコストを下回ることがある。本リポはどれにも当てはまらないため、現行方針が妥当。

- 組織のコンプライアンス要件で、IAM 変更を IaC ではなくチケット／変更承認会議ベースで運用する必要がある
- IAM ロールの変更頻度が極端に低く、IaC の追加学習コスト・メンテコストの方が大きい
- 1 つの AWS アカウントに無関係なプロジェクトが多数同居しており、Terraform 実行ロールに IAM の広い権限を与えること自体が許容できない

### まとめ

**本リポの現行方針（Terraform 実行ロールだけ手動 + 他は Terraform 管理）は維持してよい。** 注意点は以下の 2 点だけ:

1. Terraform 実行ロールの IAM 権限は、ロール名プレフィックス等で **作成可能なリソース範囲を絞り込む** こと。
2. 重要なロールには `lifecycle { prevent_destroy = true }` を検討するか、`terraform destroy` の運用ルールで保護すること。

