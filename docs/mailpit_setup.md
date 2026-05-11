# Mailpitセットアップガイド

## 概要
開発環境でメール送信をテストするために、Mailpitを使用します。

## Mailpitの起動
`docker-compose.yml`でMailpitコンテナが起動します。

## Mailpit Web UIへのアクセス
ブラウザで `http://localhost:8025` にアクセスすると、送信されたメールを確認できます。

## 環境変数の設定
`.env`ファイルに以下の設定を追加してください：

```
MAIL_MAILER=smtp
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_FROM_ADDRESS="hello@example.com"
MAIL_FROM_NAME="${APP_NAME}"
```

## 動作確認
メール送信機能を使用して、Mailpit Web UIでメールが受信されることを確認してください。










