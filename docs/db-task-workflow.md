# `db-task.yml` — DB 運用タスクの統合ワークフロー

## 1. 概要

`.github/workflows/db-task.yml` は、ECS 上で動く Laravel に対して以下の運用タスクを **GitHub Actions の workflow_dispatch から1本のワークフロー** で実行できるようにしたものです。

- `php artisan migrate --force`（マイグレーション適用）
- `php artisan db:seed --force`（シーダー実行）
- 任意のシェルコマンド（`php artisan migrate:status` / `php artisan tinker --execute='...'` / `php artisan cache:clear` 等）

旧構成では `migrate.yml` と `seeder.yml` の2本に分かれており、運用で発生する非定型 DB 作業（特定ユーザーのフラグ修正、マイグレーション状態確認、キャッシュクリア等）は SSH 接続や ECS Exec を都度開ける必要がありました。本ワークフローはそれらを **承認フロー付きで安全に流せる単一窓口** に統合しています。

設計思想は [keisuke69 氏の記事「GitHub Actions と ECS Run Task で DB 操作自動化」](https://www.keisuke69.net/entry/2026/05/02/173529) を参考にしていますが、**コマンドの渡し方** で意図的に方針を変えています（詳細は §2）。本プロジェクトでは `entrypoint.sh` を使わず ECS の `containerOverrides.command` を直接上書きする方式を採用したため、Laravel イメージ側 (`docker/ecr/backend/Dockerfile`) には変更を加えていません。

## 2. keisuke69 氏のアプローチとの差分（entrypoint.sh vs containerOverrides）

両者とも「GitHub Actions の `workflow_dispatch` から ECS RunTask を叩き、短命タスクで DB 操作を実行する」という大枠は同じです。違いは **コマンドをどこで分岐させるか** の一点に集約されます。

### keisuke69 氏の方式: イメージ内の `entrypoint.sh` で分岐

keisuke69 氏は Docker イメージに `entrypoint.sh` を組み込み、`DB_COMMAND` 環境変数の値で実行内容を切り替えます。

```bash
#!/bin/sh
case "${DB_COMMAND:-}" in
  migrate)            npx prisma migrate deploy ;;
  seed-master)        node scripts/seed-master.js ;;
  seed-dev)           node scripts/seed-dev.js ;;
  patch)              node scripts/patch.js ;;
  generate-tts-cache) node scripts/tts-cache.js ;;
  "")                 exec "$@" ;;  # 未設定なら通常のアプリ起動経路へ
  *) echo "unknown DB_COMMAND: $DB_COMMAND" >&2; exit 1 ;;
esac
```

> 上記はあくまで概念図で、記事中の実コードを写したものではありません。記事の説明から本プロジェクト向けに再構成しています。

ワークフロー側からは `containerOverrides.environment` で `DB_COMMAND=seed-master` のような **シンボル名だけを渡せばよい** ため、ワークフロー YAML はスクリプトのパスや引数を一切知らずに済みます（任意コマンドを流す custom-script モードのみ `containerOverrides.command` 経由で渡す、というハイブリッド構成）。

この方式が選ばれた背景には、keisuke69 氏側のプロジェクトに **`seed-master` / `seed-dev` / `patch` / `generate-tts-cache` といったドメイン固有の named operation が複数ある** ことが挙げられます。これらは単一の CLI コマンドでは表せず、複数ステップやプロジェクト固有のスクリプトを内包するため、イメージ内に名前付きで閉じ込めるメリットが大きい構成です。また、用途ごとにイメージを分けると依存関係の差分でバグが出やすいため、**1 つのイメージで全用途を賄う** ことを優先しており、その分岐ハブが `entrypoint.sh` という位置づけになっています。

### 本プロジェクトの方式: ワークフロー側で `containerOverrides.command` を直接組み立てる

本プロジェクトでは `entrypoint.sh` は持たず、§5 Step 4 にあるとおりワークフロー YAML 内で `case "$COMMAND_TYPE"` を分岐させ、`containerOverrides.command` をその場で組み立てて run-task に渡します。タスク定義 `runner-task` は `command` を持たないため、毎回ワークフローから与える `command` がそのまま実行コマンドになります。

### 両者の比較

| 観点 | keisuke69 氏 | 本プロジェクト |
|---|---|---|
| 分岐の置き場所 | イメージ内 `entrypoint.sh`（`DB_COMMAND` の case） | ワークフロー YAML (`case "$COMMAND_TYPE"`) |
| containerOverrides の使い方 | 主に `environment` で `DB_COMMAND` を渡す（custom-script のみ `command`） | 常に `command` を直接上書き |
| Dockerfile への変更 | `entrypoint.sh` の追加が必要 | 不要（本番 API イメージそのまま使う） |
| 名前付きカスタム操作 | イメージ内スクリプトとして同梱 | `shell` モードで都度コマンドを書く |
| ワークフローから見える情報 | シンボル名のみ（実体はイメージを読まないと分からない） | 実行コマンドそのもの |
| 想定ユースケース | named operation が多数ある中〜大規模プロジェクト | named operation が migrate/seed の 2 種で済むシンプル構成 |

### 本プロジェクトが `entrypoint.sh` を採用しなかった理由

1. 必要なオペレーションが `migrate` / `seed` / 任意 `shell` の 3 種しかなく、`migrate` と `seed` は単一 artisan コマンドで済むため、イメージ内に複数行スクリプトを閉じ込める必要がない。
2. 任意コマンドは `shell` モードで取れるようにしてあるため、keisuke69 氏が増やしていったような named operation は GitHub Actions の入力欄に直接書けば足りる。
3. `runner-task` 用イメージを本番 API イメージ (`docker/ecr/backend/Dockerfile`) と完全同一にしておきたい。`entrypoint.sh` を入れると API 起動経路にも影響しうるため、イメージに手を入れずに ECS の `containerOverrides.command` で完結させる方が副作用が小さい。
4. ワークフロー YAML を読めば「このジョブが何を実行するか」が `command` 配列で完全に見える。`DB_COMMAND=foo` の `foo` がイメージの中で何にマップされているかを別ファイルで追う必要がない。コマンドの所在がワークフロー側に一元化される。

要するに **どちらが優れているという話ではなく、ドメイン固有スクリプトをいくつ持つかで自然と選び方が決まる** という整理です。本プロジェクトで named operation が増えてきたら、その時点で `entrypoint.sh` 方式への移行を検討するタイミングになります。

## 3. なぜ ECS Exec ではなく GitHub Actions 経由か

| 観点 | ECS Exec | `db-task.yml` 経由 |
|---|---|---|
| 承認フロー | なし（権限を持つ個人がそのまま入れる） | GitHub Environments の承認 + `confirm_prod=yes` の二重ゲート |
| 監査ログ | CloudTrail に残るが個人の作業ログは断片的 | GitHub Actions のジョブログ + CloudWatch Logs (`runner` プレフィックス) に揃う |
| IAM 境界 | SSM Session Manager を経由するため広めの権限が個人に張りつきがち | `gha_db_runner_role` が `runner-task:*` の RunTask しかできず、最小権限を保てる |
| 再現性 | コマンドはオペレーターが手で入力（タイポリスク） | GitHub Actions UI に入力履歴が残る |

非定型作業をすべて GitHub Actions に通す運用の方が、何が誰にいつ実行されたかをあとから追跡しやすく、レビュー圧もかけやすくなります。

## 4. 入力パラメータ

| 入力 | 必須 | 内容 |
|---|---|---|
| `target_env` | ✅ | `stg` / `prod` の選択。`environment: ${{ inputs.target_env }}` に渡されるため GitHub Environments の承認ルールが効く |
| `command_type` | ✅ | `migrate` / `seed` / `shell` のいずれか |
| `shell_command` | △ | `command_type=shell` のときのみ使用。`bash -lc "<入力文字列>"` として実行される |
| `confirm_prod` | △ | `target_env=prod` のとき `yes` を要求。ステージから本番への意図しない実行を物理的に止める |

## 5. 処理フロー

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

## 6. シェルインジェクション対策

`command_type=shell` ではユーザーの自由入力 `shell_command` を実行することになりますが、`jq --arg c "$SHELL_COMMAND"` で **JSON 文字列としてエスケープ** したうえで `["bash","-lc",$c]` の **第3引数** に渡しているため、入力に何が入っていても shell 側でメタ文字解釈されません。

例えば `shell_command='rm -rf /; echo PWNED'` を入力しても、`bash -lc` の単一引数として渡されるので `bash` の中で1行のコマンド列として解釈されはしますが、**ワークフローシェルや AWS CLI の引数構造を破壊することはありません** (= run-task コマンド全体を乗っ取る攻撃は不可能)。`shell_command` 自体が任意コマンドなのでコンテナ内の挙動はオペレーターの責任ですが、ワークフロー外への漏洩・横展開は防げます。

## 7. 権限境界

`gha_db_runner_role` の IAM ポリシー (`terraform/modules/app-infrastructure/iam_policy_github_actions.tf` の `gha_db_runner_policy`) は以下のみを許可:

- `ssm:GetParameter` — `/practice/${env}/subnet_id_a`, `/practice/${env}/security_group_id` のみ
- `ecs:RunTask` — `practice-${env}-runner-task:*` のみ（他のタスク定義は不可）
- `ecs:DescribeTasks` — `practice-${env}-cluster` のみ
- `iam:PassRole` — `ecs_task_execution_role` / `ecs_task_role` のみ（`ecs-tasks.amazonaws.com` 限定）

これにより、たとえ db-task.yml の手元で別のタスク定義名を指定しても **AccessDenied** で蹴られます。`runner-task` 経由でしか DB に到達できない構造です。

## 8. prod 安全ゲート

| ゲート | 設定箇所 | 効果 |
|---|---|---|
| GitHub Environments 承認ルール | GitHub UI: Settings → Environments → `prod` → Required reviewers | 指定された承認者の許可がないとジョブが pending のまま進まない |
| `confirm_prod=yes` 入力必須 | `db-task.yml` の Validate inputs ステップ | 入力欄を埋めなければジョブが exit 1 でブロック |
| trust policy の `sub` / `ref` 制約 | `gha_db_runner_role` の OIDC trust | environment:prod かつ main ブランチでないと AssumeRole 不可 |

3 つすべてを通過しないと本番に到達できません。

## 9. 使用例

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

### Laravel ログの末尾確認

UI 入力:
- `target_env`: `stg`
- `command_type`: `shell`
- `shell_command`: `tail -n 200 storage/logs/laravel.log`

CloudWatch Logs に到達する前のアプリログを確認したいときに使えます。

### コンテナのディスク使用量確認

UI 入力:
- `target_env`: `stg`
- `command_type`: `shell`
- `shell_command`: `df -h && du -sh storage/* 2>/dev/null`

`storage/` 配下が肥大化していないか、タスク用コンテナのディスクに余裕があるかの簡易確認用です。

### インストール済みパッケージの確認（composer.lock 読み）

UI 入力:
- `target_env`: `prod`
- `command_type`: `shell`
- `shell_command`: `grep -E '"name"|"version"' composer.lock | head -n 100`
- `confirm_prod`: `yes`

本番イメージは `composer-builder` ステージで `vendor/` だけ取り込む構成のため、`composer` CLI は同梱されていません (`docker/ecr/backend/Dockerfile`)。インストール済みパッケージのバージョンを照合したいときは `composer.lock` を直接読みます。

### DB 接続疎通確認（PHP 経由）

UI 入力:
- `target_env`: `stg`
- `command_type`: `shell`
- `shell_command`: `php -r '$p=new PDO("mysql:host=".getenv("DB_HOST").";dbname=".getenv("DB_DATABASE"),getenv("DB_USERNAME"),getenv("DB_PASSWORD"));echo $p->query("SELECT NOW(),VERSION()")->fetch(PDO::FETCH_NUM)[1].PHP_EOL;'`

コンテナには `mysql` クライアントが入っていないため、生 SQL を投げたい場合は `pdo_mysql` 拡張経由で PHP から繋ぐか、Laravel 経由なら `php artisan db:show` / `php artisan db:monitor` を使います。

## 10. コンテナ内で使えるコマンド

`runner-task` は本番 API と同じ `docker/ecr/backend/Dockerfile` でビルドされたイメージを使うため、Laravel 実行に必要なものだけが入っており、デバッグ向けツールは最小限です。

### 入っているもの

| カテゴリ | コマンド | 由来 |
|---|---|---|
| シェル / 基本 GNU coreutils | `bash`, `sh`, `ls`, `cat`, `head`, `tail`, `grep`, `sed`, `awk`, `find`, `cp`, `mv`, `rm`, `mkdir`, `chmod`, `chown`, `wc`, `sort`, `uniq`, `xargs`, `tee`, `cut`, `df`, `du`, `date`, `env` | `php:8.2-fpm-bullseye` ベース |
| ネットワーク | `curl` | ベースイメージ同梱 |
| アーカイブ / VCS | `git`, `unzip`, `tar`, `gzip` | Dockerfile の `apt-get install` |
| 画像処理 | `convert`, `mogrify`, `identify` (ImageMagick) | Dockerfile の `apt-get install imagemagick` |
| PHP | `php` (8.2), `php-fpm`, `install-php-extensions` | ベース + `mlocati/install-php-extensions` |
| PHP 拡張 | `gd`, `pdo_mysql`, `mbstring`, `zip`, `pcntl`, `bcmath`, `imagick`, `opentelemetry` | `docker-php-ext-install` / `pecl` |
| Laravel | `php artisan ...` 全般 | `backend/www/` を COPY |

### 入っていないもの（よく欲しくなるが使えない）

| コマンド | 代替 |
|---|---|
| `mysql` / `mysqldump` | `php -r '...PDO...'` または `php artisan db:show` / `db:monitor` / `tinker` |
| `composer` (CLI) | `composer.lock` を `grep`/`cat` で読む。インストール操作はビルド時に完結している |
| `psql`, `redis-cli` | 同じく PHP から接続する |
| `vim`, `nano`, `less` | `cat` / `tail` / `head` で代用。コンテナ内ファイル編集は原則しない |
| `ps`, `top`, `htop` | `procps` 未導入。プロセス状態は CloudWatch / ECS 側で確認 |
| `ssh`, `nc`, `telnet` | コンテナから他ホストへの対話接続は想定外 |
| `jq` | コンテナ内では未導入（ワークフロー側のランナーには入っている） |

足りないツールが恒常的に必要になったら、`docker/ecr/backend/Dockerfile` 側に `apt-get install` を足す判断になります。ただし本イメージは API として常時稼働する本番イメージでもあるため、**デバッグ目的でのパッケージ追加はイメージサイズと攻撃面の増加を伴う** ことに注意してください。

## 11. 実行結果の確認

| 確認場所 | 内容 |
|---|---|
| GitHub Actions のジョブログ | run-task 開始 / 完了 / exit code |
| CloudWatch Logs `${log_group}` の `runner` プレフィックス | コンテナの標準出力（artisan の出力等）|
| `aws ecs describe-tasks` の `stoppedReason` | タスク異常終了時の AWS 側の理由 |

ロググループ名は Terraform の `aws_cloudwatch_log_group.ecs_log.name` から確定します。

## 12. 関連ファイル

| 種類 | パス | 内容 |
|---|---|---|
| ワークフロー本体 | `.github/workflows/db-task.yml` | 入力受付 → run-task → 完了待ち |
| タスク定義 (Terraform) | `terraform/modules/app-infrastructure/ecs_tasks.tf` の `aws_ecs_task_definition.runner` | family / cpu / memory / env / secrets / log config |
| IAM ロール | `terraform/modules/app-infrastructure/iam_github_actions.tf` の `module.gha_db_runner_role` | OIDC trust + ポリシーアタッチ |
| IAM ポリシー | `terraform/modules/app-infrastructure/iam_policy_github_actions.tf` の `aws_iam_policy.gha_db_runner_policy` | RunTask / DescribeTasks / PassRole / SSM Read を最小権限で許可 |
| ecspresso 設定 | `ecspresso/stg/runner/ecspresso.yml`, `ecs-task-def.jsonnet` | 新リビジョン登録時の jsonnet テンプレート（`ecspresso-update-task.yml` から register） |
| シークレット | `AWS_DB_RUNNER_ROLE_ARN` | GitHub Environments の stg / prod それぞれに登録 |
| 関連ドキュメント | [`ecspresso-deployment-pipeline.md`](./ecspresso-deployment-pipeline.md), [`github_actions_secrets.md`](./github_actions_secrets.md), [`iam_passrole_for_ecs.md`](./iam_passrole_for_ecs.md), [`ecs-config-variables.md`](./ecs-config-variables.md) | 周辺仕様 |
