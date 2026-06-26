# CLAUDE.md

このファイルは Claude Code 向けの索引と規約です。詳細は重複させず、各ドキュメントへリンクします。

## このプロジェクトは何か

React + Laravel のフルスタックアプリを **AWS (Terraform / ECS Fargate)** に本番相当で構築し、同じアプリを **GCP (Cloud Run)** に学習用として並行構築した、`kenshuu_2025` 配下の**自己学習・研修目的**のリポジトリ。フォーカスは AWS インフラ設計 (Terraform) と CI/CD 自動化。

- 概要・技術スタック・アーキ図・デプロイ構成: [README.md](./README.md)
- AWS / GCP の2文脈の地図: [CONTEXT-MAP.md](./CONTEXT-MAP.md)

## 振る舞い規約（学習優先モード）

このリポは**学ぶための場所**です。コードを動かすこと自体より、ユーザーが理解することが目的。

- **日本語で回答する。**
- **「なぜ / どうやって」を説明する。** コードを黙って書き換えるのではなく、意図・トレードオフ・仕組みを示す。
- **先回りして全部作らない。** 考える余地を残し、本人に手を動かさせる。求められた範囲を超えて実装を進めない。
- 概念やプロジェクト固有の仕組みの質問には `explain-tech`、特定コードの行ごと解説には `explain-code` スキルが使える。

## ガードレール（Claude が勝手にやらないこと）

- **状態変更系コマンドは実行しない。** `terraform apply` / `terraform destroy`、`gh` でのワークフロー起動（`terraform-apply-plan.yml`・`terraform-destroy-stg.yml`・`db-task.yml` 等）、デプロイ系コマンドは**提案にとどめ、実行はユーザーに任せる**。
- **GCP の流儀を守る。** GCP は「**コンソールで手動作成 → `terraform import` でコード化**」が原則。`gcloud` CLI でのリソース作成や `apply` による新規作成はしない。`terraform/gcp/` の `.tf` は import 先として書かれている。([docs/gcp/overview.md](./docs/gcp/overview.md))
- **Secrets / 資格情報を露出しない。** 実値のシークレット・資格情報をコミットやログに書かない。`.env` を勝手に編集しない。
- **用語の正を尊重する。** 用語の定義の正は各 `.tf` と CONTEXT.md（[ルート CONTEXT.md](./CONTEXT.md) = GCP、[terraform/CONTEXT.md](./terraform/CONTEXT.md) = AWS）。勝手に用語を作り替えない。

## コマンド

ローカル統合環境は **docker compose** が正（nginx + Laravel FPM + scheduler + MySQL + Mailpit）。

```bash
# 統合環境の起動 / 停止（Makefile も同等: make up / make down）
docker compose up -d
docker compose down
```

バックエンド (`backend/www`, Laravel 12 / PHP 8.2):

```bash
composer install
php artisan migrate
composer dev    # serve + queue:listen + pail(ログ) + vite を並列起動
composer test   # config:clear → artisan test (PHPUnit)
```

フロントエンド (`frontend/www`, React 19 / Vite 7 / TS):

```bash
npm install
npm run dev      # Vite 開発サーバ
npm run build    # tsc -b && vite build
npm run lint     # ESLint
```

詳細なローカルセットアップ: [docs/local-dev/environment_setup.md](./docs/local-dev/environment_setup.md)（Mailpit / MinIO 等は同ディレクトリ参照）。

## ディレクトリと情報の所在

| 知りたいこと | 見る場所 |
| --- | --- |
| 全体像・技術スタック・CI/CD 一覧 | [README.md](./README.md) |
| AWS / GCP の文脈分け | [CONTEXT-MAP.md](./CONTEXT-MAP.md) |
| 工夫点・改善点（Q&A サマリ） | [docs/interview-prep.md](./docs/interview-prep.md) |
| AWS インフラ設計・コスト・ECS 設定 | `docs/aws-infra/`、用語の正は [terraform/CONTEXT.md](./terraform/CONTEXT.md) |
| GCP (Cloud Run) 構成 | `docs/gcp/`、[overview.md](./docs/gcp/overview.md) |
| デプロイ (ecspresso / CodeDeploy / PR プレビュー) | `docs/deploy/` |
| 非同期処理・バッチ (SQS / 日次レポート) | `docs/app/` |
| 監視 (Sentry / CloudWatch / X-Ray) | `docs/monitoring/` |
| 設計判断の記録 | `docs/adr/` |
| アプリ実体 | `frontend/www/`（React）、`backend/www/`（Laravel） |
| IaC | `terraform/stg`・`terraform/modules`（AWS）、`terraform/gcp`（GCP） |
| ECS デプロイ定義 | `ecspresso/`（Jsonnet） |
