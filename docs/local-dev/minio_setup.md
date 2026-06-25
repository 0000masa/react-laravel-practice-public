# MinIOセットアップガイド

## 概要
開発環境でQRコードを保存するために、MinIO（S3互換オブジェクトストレージ）を使用します。

## MinIOの起動
`docker-compose.yml`でMinIOコンテナが起動します。

## バケットの作成
MinIOにバケットを作成する必要があります。以下の手順で作成してください。

### 1. MinIOコンソールにアクセス
ブラウザで `http://localhost:9090` にアクセスします。

### 2. ログイン
- Username: `minio_root`
- Password: `minio_password`

### 3. バケットの作成
1. 左側のメニューから「Buckets」を選択
2. 「Create Bucket」ボタンをクリック
3. バケット名に `qrcodes` を入力
4. 「Create Bucket」ボタンをクリック

### 4. バケットのアクセスポリシー設定（オプション）
必要に応じて、バケットのアクセスポリシーを設定してください。

## 環境変数の設定
`.env`ファイルに以下の設定を追加してください：

```
AWS_ACCESS_KEY_ID=minio_root
AWS_SECRET_ACCESS_KEY=minio_password
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=qrcodes
AWS_USE_PATH_STYLE_ENDPOINT=true
AWS_ENDPOINT=http://minio:9000
```

## 動作確認
QRコード生成機能を使用して、MinIOにファイルが保存されることを確認してください。










