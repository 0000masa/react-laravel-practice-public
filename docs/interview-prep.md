# 面接対策 Q&A（このリポジトリの工夫点・改善点）

> このドキュメントは、本リポジトリをスキルシートに掲載した際に面接官から想定される質問と、その模範回答・深掘り対策をまとめたものです。
> 主な想定読者は **インフラ / SRE / クラウド職の面接官**。技術的な深さは Terraform・ECS・CI/CD・IAM 設計に集中しているため、そこを主役に語ります。
>
> **前提として正直に言えること**: このプロジェクトは学習用だが、**stg 環境に実際に Terraform apply してデプロイし、Blue/Green デプロイ・QR 生成（同期/非同期）・メール送信・日次バッチまで動作確認済み**。「設計図を描いただけ」ではなく「実際に動かして検証した」と言える。

---

## 0. 30 秒サマリ（最初の自己紹介で使う）

React + Laravel + AWS を 1 リポジトリで通しで構築した自己学習プロジェクトです。アプリ機能（Google OAuth ログイン、QR コード生成、メール送信、日次レポート）は意図的にシンプルにし、**AWS インフラ設計（Terraform）と CI/CD 自動化（GitHub Actions OIDC + ecspresso）に技術的な力点**を置きました。特に注力したのは次の 2 点です。

1. **IAM 最小権限と OIDC によるパスワードレス CI/CD** — 用途別に 9 種のロールを切り、PassRole の二重ロックや OIDC の sub/ref 二段制約で権限昇格・横展開を防いでいます。
2. **Terraform の単一モジュール化と環境別最適化** — stg/prod を tfvars の差し替えだけで再現でき、capacity provider 変数化で stg=Spot（低コスト）/prod=オンデマンド（高可用）を切り替えられます。

stg に実デプロイして ECS ネイティブ Blue/Green まで動作確認しました。一方で、可用性・テスト自動化・WAF ルールの拡充など、本番化に向けた改善点も明確に把握しています。

---

## 目次

- [1. アーキテクチャ全体](#1-アーキテクチャ全体)
- [2. 配信経路と WAF / オリジン保護【工夫】](#2-配信経路と-waf--オリジン保護工夫)
- [3. IAM 最小権限 + OIDC【目玉の工夫】](#3-iam-最小権限--oidc目玉の工夫)
- [4. Terraform モジュール化 + 環境別最適化【目玉の工夫】](#4-terraform-モジュール化--環境別最適化目玉の工夫)
- [5. ECS デプロイ（Blue/Green・ecspresso・Jsonnet）](#5-ecs-デプロイbluegreenecspressojsonnet)
- [6. 非同期処理・バッチ・DB 運用タスク](#6-非同期処理バッチdb-運用タスク)
- [7. コスト設計](#7-コスト設計)
- [8. 可観測性](#8-可観測性)
- [9. 改善したほうがいいこと（正直に語る）](#9-改善したほうがいいこと正直に語る)
- [10. 想定される厳しい質問・ツッコミ集](#10-想定される厳しい質問ツッコミ集)

---

## 1. アーキテクチャ全体

### Q. このシステムの構成を 1 分で説明してください。

エンドユーザーのリクエストはすべて **CloudFront** を入口にします。

- **フロントエンド（SPA）**: ブラウザ → Route53 → CloudFront → S3（OAC 経由）。`/index.html` への SPA フォールバックは CloudFront Functions で実装。
- **API**: 同じ CloudFront ディストリビューションの `/api/*` ビヘイビアが、オリジンとして ALB（`api.<domain>`）に転送。**フロントと API が同一ドメイン（`www`）で配信される**ため、ブラウザからは同一オリジンに見え、CORS や Cookie の取り回しがシンプルになります。
- **アプリ実行**: ALB → ECS Fargate。Web サービス（nginx + Laravel php-fpm + Fluent Bit + ADOT のサイドカー構成）、Queue Worker サービス、日次バッチタスク、単発 Runner タスクの 4 系統。
- **データ**: RDS for **MariaDB 11.4**（Single-AZ / db.t4g.micro、stg 設定）。
- **非同期/メッセージング**: SQS（QR 非同期生成）、EventBridge（日次バッチ起動）、SES（メール送信）、SNS（アラート通知）。
- **可観測性**: CloudWatch Logs/Alarms、X-Ray（OpenTelemetry トレース）、CloudWatch Logs サブスクリプションフィルター → Lambda でエラー通知。
- **CI/CD**: GitHub Actions（OIDC でパスワードレス AWS 認証）→ ECR push → ecspresso で ECS デプロイ。フロントは S3 sync + CloudFront invalidation。

### Q. なぜアプリ機能をこんなにシンプルにしたのですか？

学習の主目的が **AWS インフラ設計と CI/CD の習得**だったためです。アプリ機能が複雑だとインフラに割ける時間が削られます。代わりに「同期 API・非同期キュー・定期バッチ・単発運用タスク」という **実運用で必ず出てくる 4 つの実行形態**を、あえて QR 生成という分かりやすい題材で一通り実装することで、ECS の Service / Queue Worker / EventBridge → RunTask / db-task といった**異なる起動方式をすべて経験する**ことを狙いました。

---

## 2. 配信経路と WAF / オリジン保護【工夫】

### Q. WAF はどこにかけていますか？すべてのリクエストを検査できますか？

**CloudFront に WAF（WebACL）をアタッチしています。** フロントエンドの静的アセットだけでなく、`/api/*` も同じ CloudFront を通すため、**フロント・API 両方のリクエストが WAF を通過**します。API 用に別の入口を作っていないのがポイントです。

### Q. ALB を直接叩かれたら WAF を迂回できてしまうのでは？（重要）

そこが一番工夫した点です。**ALB の HTTPS リスナーはデフォルトアクションを `403 Forbidden` にしてあり**、リスナールールの条件にマッチしたリクエストだけを ECS に forward します。その条件が **`X-CloudFront-Secret` ヘッダーの一致**です。

- CloudFront はオリジン（ALB）へ転送する際に、`random_password` で生成した秘密値を `X-CloudFront-Secret` カスタムヘッダーとして付与します（`cloudfront.tf`）。
- ALB のリスナールールはこのヘッダー値が一致したときだけ forward（`alb.tf` の `ecs_production` ルール）。
- そのため `api.<domain>` を**直接叩いてもヘッダーが無いので 403**。正規経路（CloudFront 経由）以外からは到達できません。

結果として「**WAF を通らないリクエストはオリジンに到達しない**」状態を作れています。これは AWS で言う **オリジン保護 / WAF バイパス防止**の典型パターンで、実コードでもこの 403 デフォルト + 秘密ヘッダー条件を確認できます。

### 深掘りされたら

- **「秘密ヘッダーは漏れたら終わりでは？」** → その通りで、現状 `random_password` は Terraform state に平文で保存され、ローテーションもしていません。より堅牢にするなら CloudFront の **VPC オリジン**や、AWS Secrets Manager + ローテーション、あるいは ALB を内部 ALB にして直接到達不可能にする手があります（改善点として §9 に記載）。
- **「images 用 CloudFront には WAF が無いですよね？」** → 事実です。画像配信用ディストリビューションは OAC で S3 を保護しているのみで WAF 未適用。公開画像のため優先度を下げましたが、レート制限の観点では適用余地があります。

---

## 3. IAM 最小権限 + OIDC【目玉の工夫】

### Q. CI/CD から AWS への認証はどうしていますか？

**GitHub Actions の OIDC によるパスワードレス認証**です。長期のアクセスキーを GitHub Secrets に置かず、ジョブ実行時に OIDC トークンで一時クレデンシャルを AssumeRole します。漏洩リスクのある静的キーをそもそも持たないのが狙いです。

### Q. ロールはどう分けていますか？

**用途別に 9 種のロール**を切っています（ECR push×2、ECS 更新×3、db-runner、s3-deploy、ecspresso、加えて Terraform 実行用）。1 つの万能ロールにせず、ワークフローごとに必要最小限の権限だけを持たせています。

### Q. OIDC の信頼ポリシーで「main ブランチかつ特定 environment」だけに絞った方法は？

GitHub OIDC の `sub` クレームは **environment 指定の有無で形式が変わる**（`...:ref:refs/heads/main` か `...:environment:stg`）ため、`sub` 単体では「environment かつ branch」の AND を表現できません。そこで:

- `sub` = `repo:.../environment:stg`（StringEquals）
- `ref` = `refs/heads/main`（StringEquals、別クレーム）

の **2 クレーム併用**で AND 制約を実現しています。さらに `aud`/`iss` は配列を取り得るため `ForAllValues:StringEquals` を使用。**`sub`/`ref` のような認証クリティカルなクレームに `ForAllValues` を使うと、欠落時に vacuously true で素通りする**（AWS が 2023 年に警告したアンチパターン）ので、そこは `StringEquals` を使い分けています。

> 補足: ECR push 系 2 ロールだけは修正ブランチからも push したいので `sub` を `:*` のワイルドカードにし、`ref` 制約を外しています（意図的な緩和）。

### Q. `iam:PassRole` を明示している理由は？

ECS タスクの登録/起動には「タスクが引き受けるロール（execution role / task role）を ECS に渡す」操作が含まれ、これに `iam:PassRole` が要ります。`AdministratorAccess` なら暗黙に通りますが、最小権限化すると明示が必要です。本リポでは:

- `Resource` を渡してよいロール ARN だけに限定
- `Condition` の `iam:PassedToService` で **渡す相手のサービスも限定**（タスク系は `ecs-tasks.amazonaws.com`、ALB 操作系は `ecs.amazonaws.com`）

という **二重ロック**で、ロールが奪取されても別アプリのロール流用や権限昇格を防いでいます。

### Q. アプリ（Laravel）が S3/SES/SQS にアクセスする認証は？

**ECS タスクロール**を使い、静的アクセスキーは一切持たせていません。ECS の web タスク定義に `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` は設定されておらず、AWS SDK がタスクロールのコンテナクレデンシャルにフォールバックします。タスクロールの権限は S3（画像バケットの Put/Get/Delete/List）・SES（`SendEmail`/`SendRawEmail` を該当ドメイン ARN に限定）・SQS（該当キュー ARN に限定）と最小権限でスコープしています。

### Q. db-task の本番実行はどう安全にしていますか？

`db-task.yml`（migrate/seed/任意 shell を ECS RunTask で実行）は **三重ゲート**です。

1. GitHub Environments の Required reviewers 承認
2. `confirm_prod=yes` 入力の必須化（stg 用 UI のまま勢いで本番実行する事故を防ぐ）
3. OIDC trust の `sub`/`ref` 制約（environment:prod かつ main）

加えて `gha_db_runner_role` は `runner-task:*` の RunTask しかできず、別タスク定義名を指定しても AccessDenied。shell モードのユーザー入力は `jq --arg` で JSON エスケープしてから `bash -lc` の第 3 引数に渡すため、ワークフローや AWS CLI の引数構造を破壊するインジェクションは不可能です。

---

## 4. Terraform モジュール化 + 環境別最適化【目玉の工夫】

### Q. Terraform の構成を説明してください。

`stg/` に直書きされていた 23 個の `.tf` を **単一モジュール `modules/app-infrastructure/`** に集約しました。ECS が RDS/S3/CloudFront/CloudWatch など多数を参照し**リソース間依存が密**なため、複数モジュールに分割すると output/variable の受け渡しが膨大になります。そこで「Terraform の modules + tfvars」パターンで、**モジュール本体は共通・環境差は tfvars だけ**という構成にしました。prod を作るときは `providers.tf`/`variables.tf`/`main.tf`/`terraform.tfvars` の 4 ファイルを置くだけで済みます。

### Q. 既存 state を壊さずにモジュール化できたのですか？

`moved` ブロックを約 80 個使い、`aws_db_instance.main` → `module.app.aws_db_instance.main` のように **state 内のアドレスだけ書き換え**ました。`moved` が無いと Terraform は destroy/create と誤判断します。state 移行は `terraform plan` の時点で完了し、結果は `0 add / 0 change / 0 destroy` になることを確認しています。`for_each`/`count` リソースはキーまで一致させる必要がある点に注意して移行しました。

### Q. 環境別の最適化はどう実現していますか？

ECS のスペック・スケール設定を **`object` 型変数**に集約し、tfvars の値だけで環境差を表現できるようにしました。特に `launch_type`（FARGATE/EC2 の 2 値のみ）を **`capacity_provider_strategy` に置き換え**、Fargate Spot を選べるようにしたのが要点です。

- **stg**: `FARGATE_SPOT` 100%（最大 70% コスト削減、停止リスクは許容）
- **prod 推奨**: `base=2` をオンデマンドで土台確保しつつ追加分を Spot に寄せる（weight 1:4）

Blue/Green の `bake_time_in_minutes` も変数化し、stg=0（即切替）/prod=30〜60（アラート発火・自動ロールバックの猶予）を切り替えられます。

> **設計判断**: 環境差のある変数は **default を置かない**方針です。default があると prod に stg 用の値が紛れ込む事故を防げないため、tfvars で必須記述させています。

### Q. なぜ RDS だけ単一 object（`rds_config`）で、ECS はサービス別に変数を分けたのですか？

意図的な使い分けです。RDS は 1 つなので単一 object でまとまりが良い。一方 ECS は web/queue/runner/batch と役割が複数あり、**tfvars を見たときにどのサービスの設定か一目で分かる**ことを優先して役割別に変数を分けました。

---

## 5. ECS デプロイ（Blue/Green・ecspresso・Jsonnet）

### Q. デプロイ方式は？CodeDeploy ですか？

web サービスは **ECS ネイティブ Blue/Green**（`deploymentConfiguration.strategy = "BLUE_GREEN"`）です。**CodeDeploy は使っていません**。ECS 自体が 2 つのターゲットグループ（slot_a/slot_b）と本番/テストリスナールールを使って切り替えるため、CodeDeploy アプリや AppSpec が不要になります。queue-worker は Rolling Update。デプロイ失敗時は `deploymentCircuitBreaker` で自動ロールバックします。

> CodeDeploy 方式との比較・移行手順は `codedeploy_ecs_deployment.md` に整理済み（聞かれたら違いを説明できる）。

### Q. ecspresso を使った理由と、Jsonnet 化の狙いは？

タスク定義/サービス定義を宣言的に管理し、`verify → diff → register → deploy` の流れで**デプロイ前に AWS 側の実体（SSM/IAM/ECR イメージ/ロググループ/ALB の実在）を検証**できるためです。Jsonnet で 5 サービス分の定義を DRY 化し、`_common.libsonnet`（モジュール本体）+ `_params.libsonnet`（環境値）で Terraform の modules+tfvars と同じ構造にしています。ECS ネイティブ B/G は SDK の対応バージョンが要るため ecspresso を `v2.8.3` に pin しています。

### Q. ecspresso 用ロールの権限が広いのはなぜ？

ecspresso が単なる register だけでなく、verify で AWS 実体を検証し、B/G 完了を polling し、tfstate プラグインが S3 を読む——と複数責務を 1 ロールで担うためです。とはいえ `Resource = "*"` は **AWS 仕様で resource-level 制約が効かない API（`ecs:DescribeServiceDeployments`、ELB Describe 系、`logs:DescribeLogGroups` 等）に限定**し、それ以外は ARN + Condition で絞っています。

---

## 6. 非同期処理・バッチ・DB 運用タスク

### Q. QR コード生成を非同期にした設計を説明してください。

`POST /api/qrcodes/async` で DB に `status=pending` で記録し SQS にエンキューして **202 を即返し**、Queue Worker タスクが QR 生成 → S3 保存 → `status=completed` 更新を行います。クライアントは `GET /api/qrcodes/{id}/status` でポーリング。失敗時は 3 回リトライ後 `failed`。重い処理を Web リクエストから切り離す典型パターンを実装しています。

### Q. 日次バッチの起動方式は？

**EventBridge（cron 0 0 \* \* ? \*）→ ECS RunTask** で、`php artisan report:daily` を単発タスクとして起動します。常駐サービスではなく都度起動なので、バッチのためにタスクを起動しっぱなしにしません。ローカルでは Laravel Scheduler に登録して同じコマンドを使えるようにしています。

> 既知の注意点: アプリのタイムゾーンが UTC のため「前日」は UTC 基準（JST 9:00 起動）。JST 基準にしたい場合は要調整、と把握しています。

### Q. 本番 DB へのマイグレーションや臨時のデータ修正はどうやりますか？

`db-task.yml` ワークフロー 1 本に集約しています。ECS Exec で個人が SSH 的に入る運用と違い、**承認フロー・監査ログ・最小権限**を担保できます。runner タスクは本番 API と同一イメージを使い、実行コマンドは `containerOverrides.command` でワークフローから渡す方式（イメージに `entrypoint.sh` を入れない）。これは「named operation が migrate/seed の 2 種で済むシンプル構成」だからで、増えてきたら entrypoint.sh 方式への移行を検討、という判断基準まで `db-task-workflow.md` に書いています。

---

## 7. コスト設計

### Q. このインフラの月額は？コスト意識はありますか？

AWS 公式料金を参照して RPS ベースで低/中/高の 3 シナリオを試算しています（`aws-cost-estimation-verified.md`）。stg 相当の**低トラフィックで月 ≈ $131（Fargate Spot ベース）**。内訳の支配項目は:

1. **NAT Gateway 36%（≈$47）** — 固定費が大きい
2. **ALB 26%（≈$34、Public IPv4 課金含む）**
3. ECS Fargate Spot 13%、RDS 12%

コスト削減のために **Fargate Spot 採用**（オンデマンド比 ≈40-50%）、**S3 Gateway VPC Endpoint で S3 トラフィックを NAT 非経由**化、stg は **RDS バックアップ無効・Single-AZ** といった割り切りをしています。

### 深掘りされたら

- **「NAT が最大コストなら減らせる？」** → ECR/Logs/SSM 用の **Interface VPC Endpoint を足せば NAT データ処理を削減**できます（未導入、改善点）。または開発時は `enable_nat_gateway=false` で止められるようにしています。
- **「Container Insights が enhanced で高い」** → 認識しています。standard に落とせば低シナリオで月 $9 程度削減できます（トレードオフ: メトリクス粒度）。

---

## 8. 可観測性

### Q. 監視・トレーシングはどうしていますか？

- **ログ**: ECS タスクは Fluent Bit（FireLens）サイドカーで CloudWatch Logs に集約。
- **トレース**: ADOT（OpenTelemetry）Collector サイドカー → X-Ray。Laravel 側も OpenTelemetry Auto-Laravel を導入。
- **アラート/通知**: CloudWatch Alarm + CloudWatch Logs サブスクリプションフィルター → Lambda → SNS でエラー通知。

サイドカー（nginx + laravel + fluent-bit + adot）をタスク内に同居させ、1 タスク = 1 単位で観測できる構成です。

---

## 9. 改善したほうがいいこと（正直に語る）

> 面接官が最も評価するのは「自分の成果物の弱点を正しく認識し、改善の道筋を語れるか」です。以下はすべて**実コードで確認済みの事実**として正直に話せます。

### 9-1. 可用性（最優先）

- **NAT Gateway 1 台 / RDS Single-AZ / `desired_count=1`**: stg のコスト最優先の割り切り。本番なら NAT を AZ ごとに冗長化、RDS は Multi-AZ、web は desired_count≥2。
- **`backup_retention_period=0`（バックアップ無し）**: stg だから無効。本番では必須。
- ただし `multi_az` / `backup_retention_period` / capacity provider はすべて **変数化済み**なので、「能力が無い」のではなく「**tfvars の値で prod 化できる設計にしてある**」と説明できる。

### 9-2. セキュリティ強化余地

- **WAF が `AWSManagedRulesCommonRuleSet` 1 個のみ**: レートベースルール（DDoS/総当たり対策）、SQLi/Bad Inputs マネージドルール、IP 評価が未適用。
- **`X-CloudFront-Secret` が Terraform state に平文・未ローテーション**: 漏洩時に WAF バイパス可能。VPC オリジン化や Secrets Manager + ローテーションで堅牢化できる。
- **images 用 CloudFront に WAF 未適用**。

### 9-3. テスト / 品質

- **PHPUnit はあるが CI で自動実行していない**（テスト用ワークフロー無し）。フロントエンドのテスト・カバレッジ計測も無し。
- 改善: GitHub Actions に test ジョブを追加し、ECR push 前のゲートにする。Larastan/PHPStan、ESLint の CI 化。

### 9-4. コスト最適化余地

- Interface VPC Endpoint 未導入で NAT データ処理費が乗る。
- Container Insights が enhanced（standard で削減可能）。

### 9-5. dev/prod parity（開発・本番の差異）

- **ローカル DB は MySQL 8.0（docker-compose）だが、本番 RDS は MariaDB 11.4**。両者は概ね互換だが、関数や予約語・厳密モードの差で「ローカルで通って本番で落ちる」リスクがある。
- 改善: ローカルも MariaDB に揃える（docker-compose の image を変更）か、本番を MySQL に揃えて parity を取る。The Twelve-Factor App の dev/prod parity 原則に沿わせる。
- 同様に、ローカルは MinIO/Mailpit、本番は S3/SES と差があるが、これは S3 互換 API・SMTP 互換で**インターフェースを揃えている**ため許容範囲（環境変数の切替のみ）。

### 9-6. db-task の本番安全策（RDS スナップショット）

`db-task.yml` は migrate / seed / 任意 shell を本番 DB に対して実行できる。承認フロー・最小権限・インジェクション対策（§3）は備えているが、**「実行したコマンド自体が DB を壊す」ケース（誤った migration、想定外の seed、`UPDATE`/`DELETE` ミス）への備えが弱い**。

- 改善: **本番で破壊的な `command_type`（migrate / seed / 書き込み系 shell）を実行する直前に手動 RDS スナップショットを取得**し、失敗時にそこから復元できるようにする。任意で実行後にも「既知の正常状態」のスナップショットを取る。
- 実装イメージ: ワークフローのバリデーション直後に `aws rds create-db-snapshot --db-snapshot-identifier <project>-pre-dbtask-<run_id>-<timestamp>` を実行し、`aws rds wait db-snapshot-available` で完了を待ってから RunTask に進む。読み取り専用 shell（`migrate:status` 等）はスキップする条件分岐を入れる。
- 必要な追加権限: `gha_db_runner_role` に `rds:CreateDBSnapshot` / `rds:DescribeDBSnapshots`（＋復元運用するなら `rds:RestoreDBInstanceFromDBSnapshot`）を、対象 DB インスタンス ARN に限定して付与する。

**深掘り耐性（必ず聞かれる）**:

- **「自動バックアップ（PITR）で足りるのでは？」** → 補完関係です。そもそも stg は `backup_retention_period=0` で自動バックアップ無効（§9-1）なので、まず本番では retention を有効化するのが前提。そのうえで「**この運用操作の直前**」という明示的な復元ポイントを名前付きで残せるのが手動スナップショットの価値で、変更前後の切り分けが容易になります。
- **「スナップショットは時間がかかる／復元はインプレースではない」** → その通りで、大規模 DB では取得・復元に時間がかかり、復元は新インスタンス作成 + エンドポイント切替になります。だから「ゼロダウンで即ロールバック」ではなく「**最悪時に確実に戻せる保険**」と位置づけ、まずは migration を後方互換（expand→contract）に設計してロールバック自体を減らすのが本筋です。
- **コスト/後始末**: 手動スナップショットは削除するまで残り課金されるため、保持世代数や TTL（古いものを定期削除）の運用もセットで考える。

---

## 10. 想定される厳しい質問・ツッコミ集

### Q. 「これ学習用ですよね？実務で通用するんですか？」

学習用ですが、**実際に stg にデプロイして動作検証**しており、机上ではありません。むしろ実務で必ず必要になる「最小権限 IAM」「パスワードレス CI/CD」「state を壊さない Terraform リファクタ」「承認フロー付き運用タスク」といった、**機能開発より運用・基盤の難所**を意図的に踏みにいった点を評価していただきたいです。改善点（可用性・テスト自動化など）も明確に把握しています。

### Q. 「Fargate Spot は本番で落ちますよね？」

はい、2 分前通知で停止し得ます。だから **stg は全 Spot（コスト優先）**、prod は `base` でオンデマンドの土台を確保しつつ追加分を Spot に寄せる戦略を変数で切り替えられるようにしています。web は Blue/Green + circuit breaker、queue worker はリトライ前提の冪等設計なので、Spot 中断にもある程度耐えます。

### Q. 「なぜ ECS ネイティブ B/G にしたんですか？CodeDeploy の方が高機能では？」

カナリア/線形のような**きめ細かいトラフィック制御が要るなら CodeDeploy**ですが、本プロジェクトは「全切替 + 失敗時自動ロールバック」で十分で、CodeDeploy アプリ・AppSpec・デプロイメントグループという**管理対象を増やさず**に Blue/Green を実現したかったため ECS ネイティブを選びました。違いと移行手順は別ドキュメントに整理済みです。

### Q. 「IAM ロールを Terraform 管理にして、Terraform 実行ロール自体が乗っ取られたら全部作れてしまうのでは？」

その通りで、Terraform 実行ロールだけは**対象構成の外**で手動管理しています（ブートストラップ問題）。緩和策として、実行ロールの権限はロール名プレフィックス（`practice-*-gha-*` 等）で作成可能範囲を絞る、重要ロールに `prevent_destroy` を付ける、trust policy 変更は PR 必須にする、を想定しています。

### Q. 「秘密ヘッダー方式は本当に安全ですか？」

完全ではありません（§2・§9-2）。state 平文・未ローテーションが弱点で、より堅牢にするなら CloudFront VPC オリジンや内部 ALB 化が筋です。現状は「**WAF を必ず通す**」という目的に対する実装コストの低い解として採用し、限界も把握している、というのが正直なところです。

### Q. 「db-task で本番 DB を壊したらどう戻すんですか？」

現状は承認フロー・最小権限・インジェクション対策はありますが、**「実行コマンド自体が DB を壊す」ケースのロールバック手段が弱い**のが正直な改善点です（§9-6）。次にやるなら、本番で破壊的な操作（migrate/seed/書き込み shell）の**直前に手動 RDS スナップショットを取得**し、`rds wait db-snapshot-available` で完了を待ってから実行する仕組みを入れます。前提として本番では自動バックアップ（PITR）を有効化し、加えてこの「操作直前」の名前付き復元ポイントを残す、という二段構えにします。あわせて migration を後方互換（expand→contract）で設計し、そもそもロールバックが要らない形に寄せます。

### Q. 「ローカルが MySQL で本番が MariaDB なのは問題では？」

ご指摘の通り、dev/prod parity の観点では弱点です（§9-6）。MySQL と MariaDB は概ね互換ですが、厳密には差があるため、ローカルも MariaDB に揃えるのが正しい対応だと認識しています。一方ストレージ（MinIO↔S3）やメール（Mailpit↔SES）は S3 互換 API・SMTP 互換で**インターフェースを揃え、環境変数の切替だけ**で動くようにしてあり、こちらは parity を意識した設計です。

### Q. 「テストは書いてますか？」

PHPUnit のテストは置いていますが、**CI に組み込めていないのが明確な改善点**です。次にやるなら ECR push 前に test ジョブをゲートとして挟み、PHPStan/ESLint も CI 化します。

---

## 関連ドキュメント

- [README.md](../README.md) — 全体像
- [github_actions_secrets.md](./deploy/github_actions_secrets.md) — OIDC sub/ref・ForAllValues の罠
- [iam_passrole_for_ecs.md](./aws-infra/iam_passrole_for_ecs.md) — PassRole 二重ロック
- [module-refactoring.md](./aws-infra/module-refactoring.md) — 単一モジュール化・moved ブロック
- [ecs-config-variables.md](./aws-infra/ecs-config-variables.md) — capacity provider 変数化・bake time
- [ecspresso-deployment-pipeline.md](./deploy/ecspresso-deployment-pipeline.md) — B/G デプロイと必要権限
- [codedeploy_ecs_deployment.md](./deploy/codedeploy_ecs_deployment.md) — CodeDeploy 方式との比較
- [db-task-workflow.md](./deploy/db-task-workflow.md) — 承認付き DB 運用タスク
- [sqs_queue_qrcode.md](./app/sqs_queue_qrcode.md) / [batch_daily_report.md](./app/batch_daily_report.md) — 非同期/バッチ
- [aws-cost-estimation-verified.md](./aws-infra/aws-cost-estimation-verified.md) — コスト試算
</content>
</invoke>
