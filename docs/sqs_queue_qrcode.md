# SQSキューによるQRコード非同期生成

## 概要

SQSキューを使ってQRコード生成を非同期に処理する機能。APIリクエスト時にJobをSQSキューに投入し、即座にレスポンスを返す。Workerプロセスがキューからジョブを取得してQRコード生成・S3アップロード・DB更新を行う。

## 処理フロー

```
クライアント → POST /api/qrcodes/async → DB(status=pending) → SQSに投入 → 202レスポンス
                                                                    ↓
                                              Worker: QR生成 → S3保存 → DB更新(status=completed)

クライアント → GET /api/qrcodes/{id}/status → ステータス確認（ポーリング）
```

## APIエンドポイント

### POST /api/qrcodes/async

非同期でQRコードを生成する。認証が必要。

**リクエスト:**
```json
{
  "data": "https://example.com"
}
```

**レスポンス (202 Accepted):**
```json
{
  "message": "QRコード生成ジョブをキューに投入しました",
  "qrcode": {
    "id": 1,
    "status": "pending",
    "data": "https://example.com",
    "created_at": "2026-02-17T12:00:00.000000Z"
  }
}
```

### GET /api/qrcodes/{id}/status

QRコードの生成ステータスを確認する。認証が必要。

**レスポンス（pending時）:**
```json
{
  "id": 1,
  "status": "pending",
  "data": "https://example.com",
  "created_at": "2026-02-17T12:00:00.000000Z",
  "updated_at": "2026-02-17T12:00:00.000000Z"
}
```

**レスポンス（completed時）:**
```json
{
  "id": 1,
  "status": "completed",
  "data": "https://example.com",
  "url": "https://s3.amazonaws.com/bucket/1_1708171200_abc123.png",
  "file_name": "1_1708171200_abc123.png",
  "created_at": "2026-02-17T12:00:00.000000Z",
  "updated_at": "2026-02-17T12:00:05.000000Z"
}
```

**ステータス一覧:**

| ステータス | 説明 |
|---|---|
| `pending` | キューに投入済み、処理待ち |
| `completed` | QRコード生成・S3保存完了 |
| `failed` | 生成失敗（3回リトライ後） |

## 関連ファイル

| ファイル | 説明 |
|---|---|
| `app/Http/Controllers/QrCodeQueueController.php` | 非同期QR生成・ステータス確認コントローラー |
| `app/Jobs/GenerateQrCodeJob.php` | SQSキューで実行されるJobクラス |
| `app/Models/QrCode.php` | ステータス定数追加済み |
| `database/migrations/2026_02_17_000001_*` | `status` カラム追加マイグレーション |
| `routes/api.php` | ルート定義 |

## 環境変数

`.env` に以下を設定する:

```bash
# SQSを使う場合
QUEUE_CONNECTION=sqs
SQS_PREFIX=https://sqs.ap-northeast-1.amazonaws.com/123456789012
SQS_QUEUE=qrcode-generation

# ローカル開発時はdatabaseドライバを使用
QUEUE_CONNECTION=database
```

## ローカルでの動作確認

```bash
# 1. マイグレーション実行
php artisan migrate

# 2. QUEUE_CONNECTION=database で .env を設定

# 3. キュー処理用のジョブテーブルを作成（初回のみ）
php artisan queue:table
php artisan migrate

# 4. API経由でジョブを投入（認証後）
curl -X POST http://localhost/api/qrcodes/async \
  -H "Content-Type: application/json" \
  -d '{"data": "https://example.com"}'

# 5. Workerを起動してジョブを処理
php artisan queue:work --queue=qrcode-generation

# 6. ステータスを確認
curl http://localhost/api/qrcodes/1/status
```

## AWS デプロイ設定

### SQS キュー作成

```
キュー名: qrcode-generation
タイプ: 標準キュー
可視性タイムアウト: 90秒
メッセージ保持期間: 4日
```

### ECS タスク定義（Worker用）

Webサーバーとは別に、キューworker用のECSサービスを作成する。

```json
{
  "containerDefinitions": [
    {
      "name": "queue-worker",
      "image": "<ECRリポジトリURL>:latest",
      "command": ["php", "artisan", "queue:work", "sqs", "--queue=qrcode-generation", "--tries=3", "--timeout=60"],
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/queue-worker",
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
