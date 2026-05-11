# `db-task.yml` — DB 運用タスクの統合ワークフロー

## 1. 概要

`.github/workflows/db-task.yml` は、ECS 上で動く Laravel に対して以下の運用タスクを **GitHub Actions の workflow_dispatch から1本のワークフロー** で実行できるようにしたものです。

- `php artisan migrate --force`（マイグレーション適用）
- `php artisan db:seed --force`（シーダー実行）
- 任意のシェルコマンド（`php artisan migrate:status` / `php artisan tinker --execute='...'` / `php artisan cache:clear` 等）

旧構成では `migrate.yml` と `seeder.yml` の2本に分かれており、運用で発生する非定型 DB 作業（特定ユーザーのフラグ修正、マイグレーション状態確認、キャッシュクリア等）は SSH 接続や ECS Exec を都度開ける必要がありました。本ワークフローはそれらを **承認フロー付きで安全に流せる単一窓口** に統合しています。

設計思想は [keisuke69 氏の記事「GitHub Actions と ECS Run Task で DB 操作自動化」](https://www.keisuke69.net/entry/2026/05/02/173529) を参考にしていますが、`entrypoint.sh` を使わず **ECS の `containerOverrides` で `command` を直接上書きする方式** を採用したため、Laravel イメージ側 (`docker/ecr/backend/Dockerfile`) には変更を加えていません。

## 2. なぜ ECS Exec ではなく GitHub Actions 経由か

| 観点 | ECS Exec | `db-task.yml` 経由 |
|---|---|---|
| 承認フロー | なし（権限を持つ個人がそのまま入れる） | GitHub Environments の承認 + `confirm_prod=yes` の二重ゲート |
| 監査ログ | CloudTrail に残るが個人の作業ログは断片的 | GitHub Actions のジョブログ + CloudWatch Logs (`runner` プレフィックス) に揃う |
| IAM 境界 | SSM Session Manager を経由するため広めの権限が個人に張りつきがち | `gha_db_runner_role` が `runner-task:*` の RunTask しかできず、最小権限を保てる |
| 再現性 | コマンドはオペレーターが手で入力（タイポリスク） | GitHub Actions UI に入力履歴が残る |

非定型作業をすべて GitHub Actions に通す運用の方が、何が誰にいつ実行されたかをあとから追跡しやすく、レビュー圧もかけやすくなります。

## 3. 入力パラメータ

| 入力 | 必須 | 内容 |
|---|---|---|
| `target_env` | ✅ | `stg` / `prod` の選択。`environment: ${{ inputs.target_env }}` に渡されるため GitHub Environments の承認ルールが効く |
| `command_type` | ✅ | `migrate` / `seed` / `shell` のいずれか |
| `shell_command` | △ | `command_type=shell` のときのみ使用。`bash -lc "<入力文字列>"` として実行される |
| `confirm_prod` | △ | `target_env=prod` のとき `yes` を要求。ステージから本番への意図しない実行を物理的に止める |

## 4. 処理フロー

```
1. Validate inputs        : prod ゲート + shell 引数チェック
2. Configure AWS Creds    : OIDC で gha_db_runner_role を AssumeRole
3. Get SSM parameters     : /practice/${env}/subnet_id_a と /security_group_id を取得
4. Build overrides JSON   : command_type 分岐 + jq で安全な JSON 生成
5. Run ECS Task           : aws ecs run-task --overrides ... で起動
6. Wait tasks-stopped     : 完了待ち
7. Check exit code        : 0 以外なら fail
```

### Step 1: Validate inputs

```bash
if [ "$TARGET_ENV" = "prod" ] && [ "$CONFIRM_PROD" != "yes" ]; then
  exit 1
fi
if [ "$COMMAND_TYPE" = "shell" ] && [ -z "$SHELL_COMMAND" ]; then
  exit 1
fi
```

`confirm_prod` を必須にすることで「stg 用 UI を開いたまま勢いで Run しても本番には届かない」状態を作っています。GitHub Environments の承認ルールと組み合わせた **二重ゲート** が prod 安全策の本体です。

### Step 2: AWS OIDC

`secrets.AWS_DB_RUNNER_ROLE_ARN` を AssumeRole します。trust policy は `sub = repo:<owner>/<repo>:environment:<env>` かつ `ref = refs/heads/main` を要求するため、選択した environment 経由かつ main ブランチからのジョブだけが通ります（詳細は [`github_actions_secrets.md`](./github_actions_secrets.md) §2-§4）。

### Step 3: SSM パラメータ取得

ECS タスクを VPC 内に起動するために subnet と security group の ID が必要ですが、これらは `module.vpc` 配下のリソースで Terraform 出力では引きにくいため、`module.app` 側で SSM Parameter Store に書き出しておき (`terraform/modules/app-infrastructure/ssm.tf`)、ワークフローから読み取ります。

```bash
SUBNET_ID_A=$(aws ssm get-parameter --name "/practice/${target_env}/subnet_id_a" ...)
SECURITY_GROUP_ID=$(aws ssm get-parameter --name "/practice/${target_env}/security_group_id" ...)
```

`gha_db_runner_role` のポリシーはこの 2 パラメータ ARN だけ `ssm:GetParameter` を許可しており、他の SSM 値は読めません。

### Step 4: containerOverrides JSON の組み立て

`command_type` で分岐して `command` 配列の中身を決めたあと、`jq` で `containerOverrides` 全体を JSON に組み立てます。

```bash
case "$COMMAND_TYPE" in
  migrate) CMD_JSON='["php","artisan","migrate","--force"]' ;;
  seed)    CMD_JSON='["php","artisan","db:seed","--force"]' ;;
  shell)   CMD_JSON=$(jq -nc --arg c "$SHELL_COMMAND" '["bash","-lc",$c]') ;;
esac

OVERRIDES=$(jq -nc \
  --arg name "$CONTAINER_NAME" \
  --argjson cmd "$CMD_JSON" \
  '{containerOverrides:[{name:$name, command:$cmd}]}')
```

ECS の `containerOverrides.command` は **タスク定義側の `command` または Docker イメージの `CMD` を上書き** します。本ワークフロー専用のタスク定義 `runner-task` は `command` を持たない設計なので、ここで毎回与える `command` がそのまま実行コマンドになります。

### Step 5-7: 実行・完了待ち・終了コード確認

```bash
TASK_ARN=$(aws ecs run-task \
  --cluster ... --task-definition ... --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={...}" \
  --overrides "$OVERRIDES" \
  --query "tasks[0].taskArn" --output text)

aws ecs wait tasks-stopped --cluster ... --tasks "$TASK_ARN"

EXIT_CODE=$(aws ecs describe-tasks ... --query "tasks[0].containers[0].exitCode" --output text)
[ "$EXIT_CODE" != "0" ] && exit 1
```

完了待ちで止まり、コンテナの exit code が 0 以外ならジョブも fail させるため、マイグレーション失敗や seed 失敗が GitHub 上で赤く表示されます。

## 5. シェルインジェクション対策

`command_type=shell` ではユーザーの自由入力 `shell_command` を実行することになりますが、`jq --arg c "$SHELL_COMMAND"` で **JSON 文字列としてエスケープ** したうえで `["bash","-lc",$c]` の **第3引数** に渡しているため、入力に何が入っていても shell 側でメタ文字解釈されません。

例えば `shell_command='rm -rf /; echo PWNED'` を入力しても、`bash -lc` の単一引数として渡されるので `bash` の中で1行のコマンド列として解釈されはしますが、**ワークフローシェルや AWS CLI の引数構造を破壊することはありません** (= run-task コマンド全体を乗っ取る攻撃は不可能)。`shell_command` 自体が任意コマンドなのでコンテナ内の挙動はオペレーターの責任ですが、ワークフロー外への漏洩・横展開は防げます。

## 6. 権限境界

`gha_db_runner_role` の IAM ポリシー (`terraform/modules/app-infrastructure/iam_policy_github_actions.tf` の `gha_db_runner_policy`) は以下のみを許可:

- `ssm:GetParameter` — `/practice/${env}/subnet_id_a`, `/practice/${env}/security_group_id` のみ
- `ecs:RunTask` — `practice-${env}-runner-task:*` のみ（他のタスク定義は不可）
- `ecs:DescribeTasks` — `practice-${env}-cluster` のみ
- `iam:PassRole` — `ecs_task_execution_role` / `ecs_task_role` のみ（`ecs-tasks.amazonaws.com` 限定）

これにより、たとえ db-task.yml の手元で別のタスク定義名を指定しても **AccessDenied** で蹴られます。`runner-task` 経由でしか DB に到達できない構造です。

## 7. prod 安全ゲート

| ゲート | 設定箇所 | 効果 |
|---|---|---|
| GitHub Environments 承認ルール | GitHub UI: Settings → Environments → `prod` → Required reviewers | 指定された承認者の許可がないとジョブが pending のまま進まない |
| `confirm_prod=yes` 入力必須 | `db-task.yml` の Validate inputs ステップ | 入力欄を埋めなければジョブが exit 1 でブロック |
| trust policy の `sub` / `ref` 制約 | `gha_db_runner_role` の OIDC trust | environment:prod かつ main ブランチでないと AssumeRole 不可 |

3 つすべてを通過しないと本番に到達できません。

## 8. 使用例

### マイグレーション適用

UI 入力:
- `target_env`: `stg`
- `command_type`: `migrate`

その他は空欄で OK。

### シーダー実行

UI 入力:
- `target_env`: `stg`
- `command_type`: `seed`

### マイグレーション状態確認

UI 入力:
- `target_env`: `stg`
- `command_type`: `shell`
- `shell_command`: `php artisan migrate:status`

### 特定ユーザーの管理者権限付与（カスタムスクリプト）

UI 入力:
- `target_env`: `prod`
- `command_type`: `shell`
- `shell_command`: `php artisan tinker --execute="App\\Models\\User::where('email','user@example.com')->update(['is_admin'=>true]);"`
- `confirm_prod`: `yes`

GitHub Environments の承認待ちを経由してから実行されます。

### キャッシュクリア

UI 入力:
- `target_env`: `stg`
- `command_type`: `shell`
- `shell_command`: `php artisan cache:clear && php artisan config:clear`

## 9. 実行結果の確認

| 確認場所 | 内容 |
|---|---|
| GitHub Actions のジョブログ | run-task 開始 / 完了 / exit code |
| CloudWatch Logs `${log_group}` の `runner` プレフィックス | コンテナの標準出力（artisan の出力等）|
| `aws ecs describe-tasks` の `stoppedReason` | タスク異常終了時の AWS 側の理由 |

ロググループ名は Terraform の `aws_cloudwatch_log_group.ecs_log.name` から確定します。

## 10. 関連ファイル

| 種類 | パス | 内容 |
|---|---|---|
| ワークフロー本体 | `.github/workflows/db-task.yml` | 入力受付 → run-task → 完了待ち |
| タスク定義 (Terraform) | `terraform/modules/app-infrastructure/ecs_tasks.tf` の `aws_ecs_task_definition.runner` | family / cpu / memory / env / secrets / log config |
| IAM ロール | `terraform/modules/app-infrastructure/iam_github_actions.tf` の `module.gha_db_runner_role` | OIDC trust + ポリシーアタッチ |
| IAM ポリシー | `terraform/modules/app-infrastructure/iam_policy_github_actions.tf` の `aws_iam_policy.gha_db_runner_policy` | RunTask / DescribeTasks / PassRole / SSM Read を最小権限で許可 |
| ecspresso 設定 | `ecspresso/stg/runner/ecspresso.yml`, `ecs-task-def.jsonnet` | 新リビジョン登録時の jsonnet テンプレート（`ecspresso-update-task.yml` から register） |
| シークレット | `AWS_DB_RUNNER_ROLE_ARN` | GitHub Environments の stg / prod それぞれに登録 |
| 関連ドキュメント | [`ecspresso-deployment-pipeline.md`](./ecspresso-deployment-pipeline.md), [`github_actions_secrets.md`](./github_actions_secrets.md), [`iam_passrole_for_ecs.md`](./iam_passrole_for_ecs.md), [`ecs-config-variables.md`](./ecs-config-variables.md) | 周辺仕様 |
