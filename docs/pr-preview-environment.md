# PR ごとの検証環境（preview 環境）

PR を作るたびに、その PR のコードで動く**本番相当のフルスタック（React + Nginx + Laravel / S3 + CloudFront + ALB + ECS + RDS）**を専用サブドメインに立ち上げ、PR クローズで破棄する仕組み。本番（stg）の構成を**忠実に再現**してレビュー/QA することを目的とする。

## 全体構成

```
[ブラウザ]
   │  https://pr-<n>.preview.example.com   (Basic 認証 = WAF)
   ▼
[CloudFront：PR ごとに 1 枚]
   ├─ /            → S3 frontend(共有バケット)/pr-<n>/   ← SPA を origin_path で配信
   └─ /api/*       → origin: preview-api.example.com(共有/ALB)
                      ・X-CloudFront-Secret を注入（本番同様の 403 ゲート）
                      ・all_viewer ポリシーで Host(pr-<n>.preview...) を ALB に転送
   ▼
[ALB(本番と同じ ALB の HTTPS リスナー)]
   └─ リスナールール(PR ごと, priority=20000+n)
        条件: host-header = pr-<n>.preview.example.com かつ X-CloudFront-Secret 一致
        → forward: preview-pr<n>-tg
   ▼
[ECS service: preview-pr<n>-web]  (react-nginx + laravel, desired_count=1, Fargate Spot)
   └─ /api を同居 laravel-fpm へ、それ以外は SPA を配信
   ▼
[共通 RDS(stg と同一インスタンス)] → database: preview_pr<n>（preview ユーザーで接続）
```

補足:
- **viewer ホスト（`pr-<n>.preview`）と API オリジンホスト（`preview-api`）を分ける**のは本番（`www` と `api`）と同じ理由。同一ホストを CloudFront 向き（viewer）と ALB 向き（origin）の両方に向けられないため。`preview-api.example.com` は **全 PR 共通**の Route53 レコード → ALB。CloudFront は `all_viewer` で viewer の Host を転送するので、ALB は `pr-<n>.preview...` を見て PR を識別できる。
- フロントは `import.meta.env.VITE_API_BASE_URL || '/api'`。preview では `VITE_API_BASE_URL` 未設定＝**相対 `/api`** なので、サブドメインが変わってもフロントの再ビルドは不要。

## PR ごとに作るもの / 共有するもの

| リソース | 単位 | 命名・補足 |
|---|---|---|
| CloudFront ディストリビューション | **PR ごと** | viewer = `pr-<n>.preview.example.com` |
| Route53 A/AAAA レコード(viewer) | **PR ごと** | `pr-<n>.preview` → 当該 CloudFront |
| ALB ターゲットグループ | **PR ごと** | `preview-pr<n>-tg` / health `GET /api/health` / target-type ip |
| ALB リスナールール | **PR ごと** | priority `20000 + n` / 条件: host + X-CloudFront-Secret |
| ECS web サービス + タスク定義 | **PR ごと** | `preview-pr<n>-web`（react-nginx + laravel） |
| ECS queue-worker + SQS キュー | **PR ごと** | `preview-pr<n>-qrcode-generation`（ジョブ取り違え防止に分離必須） |
| runner タスク定義 | **PR ごと** | `preview-pr<n>-runner`（PR イメージ・`DB_DATABASE=preview_pr<n>`・`DB_USERNAME=preview` を焼き込み） |
| RDS database | **PR ごと** | `preview_pr<n>`（共通インスタンス上） |
| IAM タスクロール | **PR ごと** | `/preview/` パス + Permissions Boundary 必須 |
| 画像 S3 バケット + 画像 CloudFront | **共有(1 回作成)** | QR 画像は uniqid 付きで衝突せず混在無害 |
| frontend S3 バケット | **共有** | `pr-<n>/` プレフィックスで分離、CloudFront の `origin_path=/pr-<n>` |
| `preview-api` Route53 → ALB | **共有** | 全 PR CloudFront の `/api` オリジン |
| ワイルドカード ACM 証明書 | **共有(1 回作成)** | `*.preview.example.com`（CloudFront 用は us-east-1、ALB 用は ap-northeast-1） |
| WAF Web ACL(Basic 認証) | **共有(1 回作成, us-east-1)** | 各 PR CloudFront に関連付け |
| エラー通知 Lambda | **作らない** | PR ごとにエラーメールが飛ぶとスパムになるため |

## IaC / state

- 専用ルートモジュール `terraform/pr-env/`。**backend のキーを PR ごとに差し替え**て state を分離（`key = "preview/pr-<n>/terraform.tfstate"`）。workspace は使わない（CI での選択ミス事故を避ける）。
- ECS は本番のような Blue/Green は使わず、**Terraform が `image_tag` を変数で受けて単純なローリングのサービス/タスク定義として管理**（ecspresso 不使用）。
- **DB の database 作成/削除だけは Terraform 管理外**（MySQL の database を Terraform で管理しない）。runner タスク経由で実行する。

## アクセス制御

- 唯一の公開面は **PR ごとの CloudFront**。ALB は `X-CloudFront-Secret` 無しを 403 で弾くので、ALB/ECS への直接到達経路は無い。
- CloudFront に **WAF(Basic 認証)** を関連付ける。WAF は `Authorization` ヘッダを検査し、不一致なら **401 + `WWW-Authenticate: Basic realm="preview"`** のカスタムレスポンスを返す（IP 非依存）。資格情報は SSM 管理の共有 1 組。
- preview では **Google ログインを無効化**（`AUTH_GOOGLE_ENABLED=false` / フロントは `VITE_AUTH_MODE=password`）。Google の承認済みリダイレクト URI はワイルドカード不可で PR ごとの URI を登録できないため。検証は**シーダーで作るテストユーザー + パスワードログイン**で行う。
- メールは `MAIL_MAILER=ses` のまま、`AppServiceProvider` で `Mail::alwaysTo(config('mail.preview_redirect_to'))` により **stg/preview の全送信先を固定アドレスに上書き**（誤送信防止）。

### preview デプロイ用 IAM ロール（重要）

- STG の AdministratorAccess ロールは**流用しない**。preview は `pull_request` で**自動発火**し PR ブランチのコードで Terraform を回すため、admin だと PR コードによる権限昇格(pwn-request)が成立してしまう。
- **preview 専用の最小権限 OIDC ロール**を用意し、**GitHub Environment `preview` 経由**で AssumeRole（Environment 保護ルール＝maintainer 承認を掛けられる）。
- IAM は **`/preview/` パス配下のロールにしか触れない**ようにし（`Resource = arn:.../role/preview/*`）、**CreateRole は Permissions Boundary 付与を条件**にする（`Condition: iam:PermissionsBoundary = <boundary ARN>`）。Boundary により per-PR ロールの実効権限に上限を掛け、admin への昇格経路を塞ぐ。Boundary ポリシー自体を書き換える権限は付与しない。

## ライフサイクル

### 作成・更新（`preview` ラベルゲート）

トリガー: `pull_request: [opened, synchronize, labeled, reopened]`、条件 = **`preview` ラベルが付いた PR のみ**。

1. **同時上限チェック**: 既存 preview が 20 個以上ならワークフローを fail（ALB のルール/ターゲットグループ枠の保護）。
2. **イメージ build & ECR push**: PR のコードで react-nginx（フロント焼き込み・`VITE_API_BASE_URL` 未設定）/ laravel イメージをビルドし、PR 固有タグで push。
3. **frontend を S3 へ**: ビルド成果物を共有バケットの `pr-<n>/` プレフィックスへアップロード。
4. **`terraform apply`**（`terraform/pr-env/`、backend キー = PR 番号）: CloudFront・Route53(viewer)・TG・リスナールール・ECS web/worker サービス・SQS・runner タスク定義・per-PR IAM ロールを作成。
5. **DB 準備**（runner タスクを `aws ecs run-task` / `db-task.yml` の仕組みを流用）:
   `CREATE DATABASE preview_pr<n>` → `php artisan migrate --force` → `php artisan db:seed --force`。
   - preview ユーザーは `GRANT ALL ON \`preview\_%\`.*` を持つので、**自分で CREATE/DROP できる**（master 権限は不要）。
   - `preview` ユーザーと GRANT は**初回 1 回だけ** master で作成（ブートストラップ。`db-task.yml` の `shell` モードで実行）。
6. 完了。`https://pr-<n>.preview.example.com` が利用可能（Basic 認証で保護）。
7. 以降、ラベル付き PR への push（`synchronize`）で 2〜5 を再実行して更新。

### 削除（取りこぼし二系統）

トリガー: `pull_request: [closed, unlabeled]`（`closed` は merge/close 両方で発火）。

1. **`DROP DATABASE preview_pr<n>`**（runner タスク経由。Terraform 管理外なので先に明示実行）。
2. **`terraform destroy`**（backend キー = PR 番号）: CloudFront・Route53・TG・ルール・ECS・SQS・per-PR IAM ロールを一括削除。CloudFront は disable→削除待ちで時間がかかるため、ワークフローのタイムアウトは長めに設定。

> 夜間リーパー（孤児回収 cron）は採用しない。destroy が失敗した場合は手動で `terraform destroy` 再実行 + runner で `DROP DATABASE` を行って回収する。

## 既知の制約・前提

- **同時 preview 数の上限 = 20**（ALB のルール/ターゲットグループ枠 既定 100 を保護）。
- SES がサンドボックスの場合、`Mail::alwaysTo` の固定宛先も SES で検証済みである必要がある。
- preview は本番の CloudFront 設定（キャッシュポリシー等）を PR ごとに変えてテストする用途には使わない（アプリ挙動の検証用）。
- `APP_KEY` 等の SSM シークレットは stg のものを共有。preview ユーザーの DB パスワードは専用 SSM パラメータを用意する。
```
