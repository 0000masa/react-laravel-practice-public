<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>テストメール</title>
</head>
<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
    <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: #2563eb;">AWS ECSデプロイ練習アプリからのメール</h2>
        <div style="background-color: #f3f4f6; padding: 20px; border-radius: 8px; margin-top: 20px;">
            <p style="margin: 0;">{{ $body }}</p>
        </div>
        <p style="margin-top: 20px; color: #6b7280; font-size: 14px;">
            このメールはAWS ECSデプロイ練習アプリから送信されました。
        </p>
    </div>
</body>
</html>



