# PR ごとの検証環境（preview 環境）

PR を作るたびに、その PR のコードで動く**本番相当のフルスタック（React + Nginx + Laravel / S3 + CloudFront + ALB + ECS + RDS）**を専用サブドメインに立ち上げ、PR クローズで破棄する仕組み。本番（stg）の構成を**忠実に再現**してレビュー/QA することを目的とする。

## 全体構成

```
[ブラウザ]
   │  https://pr-<n>.preview.example.com   (Basic 認証 = CloudFront Function)
   ▼
[CloudFront：PR ごとに 1 枚]
   ├─ /            → S3 frontend(PRごとバケット)         ← SPA を配信（バケットのルート）
   └─ /api/*       → origin: preview-api.example.com(共有/ALB)
                      ・X-CloudFront-Secret を注入（本番同様の 403 ゲート）
                      ・all_viewer ポリシーで Host(pr-<n>.preview...) を ALB に転送
   ▼
[ALB(本番と同じ ALB の HTTPS リスナー)]
   └─ リスナールール(PR ごと, priority=20000+n)
        条件: host-header = pr-<n>.preview.example.com かつ X-CloudFront-Secret 一致
        → forward: preview-pr<n>-tg
   ▼
[ECS service: preview-pr<n>-web]  (nginx + laravel, desired_count=1, Fargate Spot)
   └─ 本番と同じ proxy 構成。nginx は /api を laravel-fpm へ中継するのみ。
      SPA は ECS では配信しない（S3/CloudFront 経由）。
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
| ECS web サービス + タスク定義 | **PR ごと** | `preview-pr<n>-web`（本番と同じ nginx + laravel。SPA は S3/CloudFront 配信） |
| ECS queue-worker + SQS キュー | **PR ごと** | `preview-pr<n>-qrcode-generation`（ジョブ取り違え防止に分離必須） |
| runner タスク定義 | **PR ごと** | `preview-pr<n>-runner`（PR イメージ・`DB_DATABASE=preview_pr<n>`・`DB_USERNAME=preview` を焼き込み） |
| RDS database | **PR ごと** | `preview_pr<n>`（共通インスタンス上） |
| IAM タスクロール | **PR ごと** | `/preview/` パス + Permissions Boundary 必須 |
| 画像 S3 バケット + 画像 CloudFront | **共有（既存 stg を再利用）** | QR 画像は uniqid 付きで衝突せず混在無害 |
| frontend S3 バケット | **PR ごと** | `preview-pr<n>-frontend`。当該 CloudFront のオリジン。`destroy` でバケットごと中身も削除（消し残りなし） |
| `preview-api` Route53 → ALB | **共有** | 全 PR CloudFront の `/api` オリジン |
| ワイルドカード ACM 証明書 | **共有(1 回作成)** | `*.preview.example.com`（CloudFront 用は us-east-1、ALB 用は ap-northeast-1） |
| WAF Web ACL(マネージドルール) | **共有（module の `cloudfront_waf` を再利用, us-east-1）** | 攻撃遮断用。stg frontend と全 PR CloudFront が同じ1枚を使う。**Basic 認証はこの WAF ではない**（下行） |
| Basic 認証 | **共有（stg の `spa_fallback` CloudFront Function を再利用）** | アクセス制限用。WAF ではなく CF Function（`enable_basic_auth=true`）。各 PR CloudFront の default と `/api/*` の両ビヘイビアに付与 |
| エラー通知 Lambda | **作らない** | PR ごとにエラーメールが飛ぶとスパムになるため |

## IaC / state

- 専用ルートモジュール `terraform/pr-env/`。**backend のキーを PR ごとに差し替え**て state を分離（`key = "practice/laravel/preview/pr-<n>/terraform.tfstate"`、stg と同じ `practice/laravel/` 名前空間配下に揃える）。workspace は使わない（CI での選択ミス事故を避ける）。→ workspace との比較・なぜ使わなかったかの詳細は [../notes/terraform-workspace-vs-backend-key.md](../notes/terraform-workspace-vs-backend-key.md)。
- ECS は本番のような Blue/Green は使わず、**Terraform が `image_tag` を変数で受けて単純なローリングのサービス/タスク定義として管理**（ecspresso 不使用）。
- **DB の database 作成/削除だけは Terraform 管理外**（MySQL の database を Terraform で管理しない）。runner タスク経由で実行する。

## アクセス制御

- 唯一の公開面は **PR ごとの CloudFront**。ALB は `X-CloudFront-Secret` 無しを 403 で弾くので、ALB/ECS への直接到達経路は無い。
- CloudFront に **Basic 認証（CloudFront Function 方式）** を掛ける。stg/preview 共有の `spa_fallback` 関数（viewer-request）が `Authorization` ヘッダを検査し、不一致なら **401 + `WWW-Authenticate: Basic realm="restricted"`** を返す（IP 非依存）。資格情報は SSM 管理の共有 1 組を apply 時に関数コードへ焼き込む。WAF（`cloudfront_waf`）は別レイヤで攻撃遮断（マネージドルール）を担い、全環境で1枚に集約。Basic 認証を WAF でなく CF Function にした経緯・コスト比較は ADR 0009。
- preview では **Google ログインを無効化**（`AUTH_GOOGLE_ENABLED=false` / フロントは `VITE_AUTH_MODE=password`）。Google の承認済みリダイレクト URI はワイルドカード不可で PR ごとの URI を登録できないため。検証は**シーダーで作るテストユーザー + パスワードログイン**で行う。
- メールは `MAIL_MAILER=ses` のまま、`AppServiceProvider` で `Mail::alwaysTo(config('mail.preview_redirect_to'))` により **stg/preview の全送信先を固定アドレスに上書き**（誤送信防止）。
  - **送信元(From)は stg の検証済み SES ドメイン**（`noreply@${sub_frontend_domain_name}.<domain>`）に向ける。preview の閲覧ドメイン（`preview.<domain>`）は SES 未検証なので From に使えない。これにより **preview のために Route53 へ SES 検証/DKIM レコードを足す必要はない**（stg のアイデンティティを再利用）。From ドメインは stg output `ses_domain_identity_name` 経由で pr-env に渡す。
  - SES 送信権限は **2 階建て**: per-PR タスクロール（`pr-env/iam.tf` の `SesSend`、`Resource = stg SES identity ARN`）と、その天井の **Permissions Boundary（`stg/preview_shared.tf` の `PreviewRuntimeMax`）の両方**に `ses:SendEmail`/`ses:SendRawEmail` が要る（実効権限は両者の積集合）。

### Basic 認証の仕組みと、なぜ SSM に生の `user:pass` を入れるか

CloudFront Function で実現している Basic 認証（HTTP Basic Authentication, RFC 7617）の流れを押さえると、SSM パラメータ `preview_basic_auth` の形式が決まる理由が分かる。

**① ブラウザ側の Basic 認証フロー**

1. CloudFront Function が `401 Unauthorized` ＋ `WWW-Authenticate: Basic realm="restricted"` を返す。
   - **`401` だけでも、ヘッダだけでもダメ**。この2つが揃って初めてブラウザは認証ダイアログを出す。
   - ヘッダ先頭の `Basic` が**認証方式**の指定。これを見てブラウザは「Basic 認証だ」と判断する（他に `Digest` / `Bearer` 等がある）。
2. ブラウザがログインダイアログを表示。ユーザーがユーザー名・パスワードを入力。
3. ブラウザが `ユーザー名:パスワード` を**コロン1個でつなぎ**、その文字列を **Base64 エンコード**する。
4. `Authorization: Basic <base64文字列>` を付けて再リクエスト。
5. 同じ realm/パスへの以降のリクエストでは、ブラウザがこのヘッダを**自動で付け直す**（毎回ダイアログは出ない）。

**② `realm` とは**

`realm`（レルム）は**「保護領域の名前」**で、役割は2つ：

- **表示ラベル**：ダイアログに「このサイト(preview)が認証を求めています」のように出る人間向けの目印。
- **資格情報のスコープ**：ブラウザは資格情報を「オリジン + realm」をキーにキャッシュする。同じ realm の 401 なら自動再送、別 realm なら別資格情報として扱える。

値（`"preview"`）は**任意の文字列で、認証の正否には一切関係しない**。照合はあくまで WAF 側の一致比較で行う。realm は「ラベル＋キャッシュの仕切り」にすぎない。

なお `realm="preview"` は **キー名と値で自由度が違う**：

- **キー名 `realm` は固定**（仕様で予約されたパラメータ名）。`area` 等に変えるとブラウザは realm として認識しない。
- **値 `"preview"` だけが自由**（`"staging"` でも何でもよい）。

また、ブラウザが「Basic 認証だ」と認識するトリガーは **`401` ＋ `WWW-Authenticate: Basic`（方式名）** の部分で、`realm` は省いても認証自体は成立する補足パラメータ（付けるとダイアログにラベルを出せる・資格情報をスコープできる）。

**③ なぜ SSM には生の `user:pass` を入れるのか**

CloudFront Function（module の `spa_fallback`、`terraform/modules/app-infrastructure/cloudfront.tf`）はこうなっている：

```hcl
# enable_basic_auth=true のとき関数コードに焼き込まれる判定
if (!authHeader || authHeader.value !== "Basic ${base64encode(var.basic_auth_credential)}") { return 401 }
```

関数は **SSM の生の値（`var.basic_auth_credential`）を apply 時に `base64encode()` し、ブラウザが送ってくる `Authorization: Basic <b64>` と完全一致比較**する。ブラウザは上の手順3で `preview:<pass>` を base64 化して送るので、こちらも**同じ `preview:<pass>` を base64 化**しないと一致しない。したがって SSM には「ブラウザが base64 化する**前**の生文字列」＝ `user:pass` を入れる必要がある。
（SSM に base64 後の値を入れると二重 base64 になって一致しない。手動 base64 時の末尾改行混入事故も避けられる。）→ 値の作り方は [初回セットアップ](#初回セットアップ手動-1-回だけ)を参照。
（CF Functions は実行時に SSM を読めないため、判定文字列は apply 時に関数コードへ焼き込む。`enable_basic_auth=false`＝prod では認証ブロックごと生成されず公開のまま。）

**④ Base64 は暗号化ではない → HTTPS 必須**

Base64 は誰でもデコードできる**単なるエンコード**で、暗号化ではない。`Authorization: Basic <b64>` は実質平文と同じなので、盗聴されれば資格情報が漏れる。Basic 認証は **HTTPS 前提**で使う。preview は公開面が CloudFront（HTTPS）なので満たしている。

### preview デプロイ用 IAM ロール（重要）

- STG の AdministratorAccess ロールは**流用しない**。preview は `pull_request` で**自動発火**し PR ブランチのコードで Terraform を回すため、admin だと PR コードによる権限昇格(pwn-request)が成立してしまう。
- **preview 専用の最小権限 OIDC ロール**を用意し、**GitHub Environment `preview` 経由**で AssumeRole（Environment 保護ルール＝maintainer 承認を掛けられる）。
- IAM は **`/preview/` パス配下のロールにしか触れない**ようにし（`Resource = arn:.../role/preview/*`）、**CreateRole は Permissions Boundary 付与を条件**にする（`Condition: iam:PermissionsBoundary = <boundary ARN>`）。Boundary により per-PR ロールの実効権限に上限を掛け、admin への昇格経路を塞ぐ。Boundary ポリシー自体を書き換える権限は付与しない。

## ライフサイクル

### 作成・更新（`preview` ラベルゲート）

トリガー: `pull_request: [opened, synchronize, labeled, reopened]`、条件 = **`preview` ラベルが付いた PR のみ**。

1. **同時上限チェック**: 既存 preview が 20 個以上ならワークフローを fail（ALB のルール/ターゲットグループ枠の保護）。
2. **イメージ build & ECR push**: PR のコードで nginx / laravel イメージ（本番と同じ）をビルドし、PR 固有タグで push。
3. **`terraform apply`**（`terraform/pr-env/`、backend キー = PR 番号）: frontend バケット・CloudFront・Route53(viewer)・TG・リスナールール・ECS web/worker サービス・SQS・runner タスク定義・per-PR IAM ロールを作成。
4. **frontend を S3 へ**: フロントを `VITE_API_BASE_URL` 未設定（＝相対 `/api`）・`VITE_AUTH_MODE=password` でビルドし、PR ごとのバケット（ルート）へアップロード。
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

## 初回セットアップ（手動・1 回だけ）

1. **SSM パラメータを作成**（`/practice/stg/` 配下、SecureString）:
   - `preview_db_password` — preview MySQL ユーザーのパスワード。誰も手入力しない機械用シークレットなので、強度優先でランダム生成する（記号のエスケープ事故を避けるため hex 推奨: `openssl rand -hex 32`）。
   - `preview_basic_auth` — Basic 認証資格情報を**生の `user:pass` 形式**で入れる（例: `preview:<ランダム生成したパスワード>`）。base64 化は WAF 側で `base64encode()` するので、ここに base64 後の値は入れない（手動 base64 時の末尾改行混入事故も防げる）。
2. **共有リソースを apply**: `terraform/stg` を apply すると preview 共有リソース（ワイルドカード ACM・WAF・`api.preview`→ALB・Permissions Boundary・preview デプロイロール）と output が作られる。frontend バケットは PR ごとに pr-env が作るのでここには含まれない。
3. **preview MySQL ユーザーを作成**（`db-task.yml` の `shell` モードで 1 回）:

   実行したい SQL はこれ（`<HEX>` は手順1で SSM `preview_db_password` に入れた実際の hex 値）:
   ```sql
   CREATE USER IF NOT EXISTS 'preview'@'%' IDENTIFIED BY '<HEX>';
   GRANT ALL PRIVILEGES ON `preview\_%`.* TO 'preview'@'%';
   ```

   ただし runner イメージ（`docker/ecr/backend/Dockerfile`）には **`mysql` クライアントが入っていない**（PHP の `pdo_mysql` のみ）。なので SQL は **`php -r` の PDO 経由**で流す。`db-task.yml` の `shell_command` 入力に次の1行を貼る（接続情報は runner タスクの env `DB_HOST` / `DB_USERNAME` / `DB_PASSWORD` = master/app 資格情報を使う）:
   ```bash
   php -r '$pdo=new PDO("mysql:host=".getenv("DB_HOST"),getenv("DB_USERNAME"),getenv("DB_PASSWORD"));$pdo->exec("CREATE USER IF NOT EXISTS \"preview\"@\"%\" IDENTIFIED BY \"<HEX>\"");$pdo->exec("GRANT ALL PRIVILEGES ON `preview\_%`.* TO \"preview\"@\"%\"");echo "ok\n";'
   ```

   **`<HEX>` は必ず実際のパスワード値に置き換える**（`<` `>` ごと削除して、囲いの `\"...\"` の中に hex を貼る）。`<HEX>` のまま実行すると、文字列 `<HEX>` がそのままパスワードとして設定されてしまう。入れる値は手順1で **SSM `preview_db_password` に入れたのと完全に同一**でなければならない（preview-create の per-PR runner はこの SSM 値で `preview` ユーザーとして接続するため。ズレると `1045 Access denied` になる）。SSM の実値はこれで確認できる:
   ```bash
   aws ssm get-parameter --name /practice/stg/preview_db_password --with-decryption --query Parameter.Value --output text
   ```
   **パスワードを間違えた／上書きしたい場合**は `CREATE USER` では直せない（`IF NOT EXISTS` は既存ユーザーのパスワードを更新しないため）。**`ALTER USER` で上書き**する。同じく `db-task.yml`（stg / shell）の `shell_command` に貼る:
   ```bash
   php -r '$pdo=new PDO("mysql:host=".getenv("DB_HOST"),getenv("DB_USERNAME"),getenv("DB_PASSWORD"));$pdo->exec("ALTER USER \"preview\"@\"%\" IDENTIFIED BY \"<HEX>\"");echo "altered\n";'
   ```
   `<HEX>` は同様に実値へ置換し、**SSM `preview_db_password` と完全一致**させる（`< >` は消す）。

   > 💡 値がズレている／不明なときは「**1つのクリーンな値を生成 → SSM を上書き → 同じ値で `ALTER USER`**」で揃え直すのが確実。手順例:
   > ```bash
   > PW=$(openssl rand -hex 32)                                  # 1) クリーンな値を1個生成（末尾改行なし）
   > aws ssm put-parameter --name /practice/stg/preview_db_password \
   >   --type SecureString --overwrite --value "$PW"            # 2) SSM を上書き
   > echo "$PW"                                                  # 3) この値を ALTER USER の <HEX> に使う
   > ```
   > SSM 値に**末尾改行を混入させない**こと（`--value "$(openssl rand -hex 32)"` のように渡せば改行は入らない。`wc -c` が 65 なら改行混入＝不一致の原因）。

   > ⚠️ SQL を `shell_command` に**生で**（`CREATE USER ...` だけ）貼ってはいけない。`shell` モードは入力を `bash -lc "..."` として実行するため、SQL は bash コマンド扱いになって失敗する。必ず上の `php -r` 形式で渡すこと。
   > （`db-task.yml` は `--overrides` を環境変数経由で渡すよう修正済みなので、`'` や `` ` `` を含むこのワンライナーでも runner 側のクォートは壊れない。）
4. **GitHub 設定**:
   - Secret: `AWS_PREVIEW_DEPLOY_ROLE_ARN`（output `preview_deploy_role_arn`）、`PREVIEW_MAIL_REDIRECT_TO`。
     - `AWS_PREVIEW_DEPLOY_ROLE_ARN` 例（アカウントID はダミー `123456789012`、実値に置き換える）:
       `arn:aws:iam::123456789012:role/practice-stg-gha-preview-deploy-role`
     - `PREVIEW_MAIL_REDIRECT_TO` 例（ダミー、実在の検証用受信箱に置き換える）: `preview-inbox@example.com`
       （SES サンドボックス時はこの宛先も SES で検証済みである必要がある）
   - Environment `preview` を作成し、保護ルール（maintainer 承認など）を設定。
   - ラベル `preview` を作成。
5. **アプリの env（stg/preview 共通の挙動）**: `AUTH_GOOGLE_ENABLED`（preview は false）、`MAIL_PREVIEW_REDIRECT_TO`、フロントは `VITE_AUTH_MODE=password`（preview ビルド時）。

## 既知の制約・前提

- **同時 preview 数の上限 = 20**（ALB のルール/ターゲットグループ枠 既定 100 を保護）。
- SES がサンドボックスの場合、`Mail::alwaysTo` の固定宛先も SES で検証済みである必要がある。
- preview は本番の CloudFront 設定（キャッシュポリシー等）を PR ごとに変えてテストする用途には使わない（アプリ挙動の検証用）。
- `APP_KEY` 等の SSM シークレットは stg のものを共有。preview ユーザーの DB パスワードは専用 SSM パラメータを用意する。
```
