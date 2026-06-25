# 日次レポートバッチ処理

## 概要

EventBridge + ECSタスクで毎日自動実行されるバッチ処理。前日のQRコード生成アクティビティをユーザーごとに集計し、サマリーメールをSESで全ユーザーに送信する。

Laravel アプリ本体は `backend/www` 配下にあるため、ローカルで Artisan コマンドを直接実行する場合は `backend/www` ディレクトリで実行する。

## Artisan コマンド

```bash
php artisan report:daily
```

### 処理フロー

1. 前日 00:00:00 〜 23:59:59 の期間を算出
2. `qr_codes` テーブルから `user_id` ごとの生成数を集計
3. 全体サマリー（総QR生成数、アクティブユーザー数、最もアクティブなユーザー）を算出
4. 全ユーザーに `DailyReportMail` を送信
5. 結果をコンソールに出力

対象期間は `Carbon::yesterday()` を使って算出している。現在の `backend/www/config/app.php` では Laravel のタイムゾーンが `UTC` のため、本番実行では「前日」は UTC 基準になる。

### メール内容

| 項目 | 説明 |
|---|---|
| 件名 | 【日次レポート】{日付} QRコード生成サマリー |
| あなたのアクティビティ | そのユーザーのQRコード生成数 |
| 総QRコード生成数 | 前日の全体生成数 |
| アクティブユーザー数 | QRコードを生成したユーザー数 / 全ユーザー数 |
| 最もアクティブなユーザー | 最も多くQRコードを生成したユーザー名と件数 |

## 関連ファイル

| ファイル | 説明 |
|---|---|
| `backend/www/app/Console/Commands/SendDailyReportCommand.php` | Artisan コマンド本体 |
| `backend/www/app/Mail/DailyReportMail.php` | Mailable クラス |
| `backend/www/resources/views/emails/daily-report.blade.php` | メールHTMLテンプレート |
| `backend/www/routes/console.php` | ローカル開発用の Laravel Scheduler 設定 |
| `terraform/modules/app-infrastructure/event_bridge.tf` | EventBridge ルールと ECS ターゲット |
| `terraform/modules/app-infrastructure/ecs_tasks.tf` | Terraform 管理のバッチ用 ECS タスク定義 |
| `ecspresso/stg/batch-daily-report/ecs-task-def.jsonnet` | ecspresso 管理の stg 用タスク定義 |

## AWS デプロイ設定

### EventBridge ルール

```
スケジュール式: cron(0 0 * * ? *)   # 毎日 UTC 00:00（JST 09:00）
ターゲット: ECS タスク
```

Terraform では `aws_cloudwatch_event_rule.daily_report` と `aws_cloudwatch_event_target.daily_report` で定義している。ターゲットは `aws_ecs_task_definition.batch_daily_report` を `task_count = 1` で起動し、private subnet と `ecs_sg` を使う。

### ECS タスク定義（バッチ用）

通常のWebサーバータスクとは別に、バッチ処理用のタスク定義を作成する。現在の stg 設定では CPU `256`、メモリ `512`、capacity provider は `FARGATE_SPOT`。

Terraform 初期定義と ecspresso の stg タスク定義はいずれも Laravel コンテナで `php artisan report:daily` を実行する。ecspresso ではイメージタグを `IMAGE_TAG_LARAVEL` から解決する。

```json
{
  "containerDefinitions": [
    {
      "name": "batch-container",
      "image": "<Laravel ECRリポジトリURL>:<Laravelイメージタグ>",
      "command": ["php", "artisan", "report:daily"],
      "essential": true,
      "environment": [
        { "name": "DB_CONNECTION", "value": "mysql" },
        { "name": "LOG_CHANNEL", "value": "stderr" },
        { "name": "MAIL_MAILER", "value": "ses" }
      ],
      "secrets": [
        { "name": "DB_PASSWORD", "valueFrom": "<SSM parameter ARN>" },
        { "name": "APP_KEY", "valueFrom": "<SSM parameter ARN>" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "<ECS共通CloudWatch Logsグループ>",
          "awslogs-region": "ap-northeast-1",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ],
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "256",
  "memory": "512"
}
```

### ローカル Scheduler

`backend/www/routes/console.php` では、ローカル開発用として Laravel Scheduler にも登録している。

```php
Schedule::command('report:daily')->dailyAt('11:15');
```

本番のスケジュール管理は EventBridge が担当する。

### 動作確認（ローカル）

```bash
# Mailpit でメール受信を確認
cd backend/www
php artisan report:daily
# ブラウザで http://localhost:8025 を開いてメールを確認
```
