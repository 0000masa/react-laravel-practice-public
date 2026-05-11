<!DOCTYPE html>
<html>

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>日次レポート</title>
</head>

<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; background-color: #f9fafb; margin: 0; padding: 20px;">
    <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.08);">
        {{-- ヘッダー --}}
        <div style="background: linear-gradient(135deg, #2563eb, #7c3aed); padding: 24px 20px; text-align: center;">
            <h1 style="color: #ffffff; margin: 0; font-size: 20px;">📊 日次レポート</h1>
            <p style="color: #dbeafe; margin: 8px 0 0; font-size: 14px;">{{ $summary['report_date'] }}</p>
        </div>

        <div style="padding: 24px 20px;">
            {{-- ユーザー向けメッセージ --}}
            <p style="margin: 0 0 16px;">{{ $userName }} さん、こんにちは。</p>
            <p style="margin: 0 0 20px;">前日のQRコード生成アクティビティのサマリーをお知らせします。</p>

            {{-- あなたのアクティビティ --}}
            <div style="background-color: #eff6ff; padding: 16px; border-radius: 8px; border-left: 4px solid #2563eb; margin-bottom: 20px;">
                <h3 style="margin: 0 0 8px; color: #1e40af; font-size: 14px;">📌 あなたのアクティビティ</h3>
                <p style="margin: 0; font-size: 28px; font-weight: bold; color: #1e40af;">
                    {{ $userQrCount }} <span style="font-size: 14px; font-weight: normal; color: #6b7280;">件のQRコード生成</span>
                </p>
            </div>

            {{-- 全体サマリー --}}
            <h3 style="margin: 0 0 12px; color: #374151; font-size: 14px;">📈 全体サマリー</h3>
            <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
                <tr>
                    <td style="padding: 10px 12px; border-bottom: 1px solid #e5e7eb; color: #6b7280; font-size: 13px;">総QRコード生成数</td>
                    <td style="padding: 10px 12px; border-bottom: 1px solid #e5e7eb; text-align: right; font-weight: bold; color: #111827;">{{ $summary['total_qr_count'] }} 件</td>
                </tr>
                <tr>
                    <td style="padding: 10px 12px; border-bottom: 1px solid #e5e7eb; color: #6b7280; font-size: 13px;">アクティブユーザー数</td>
                    <td style="padding: 10px 12px; border-bottom: 1px solid #e5e7eb; text-align: right; font-weight: bold; color: #111827;">{{ $summary['active_user_count'] }} / {{ $summary['total_user_count'] }} 人</td>
                </tr>
                <tr>
                    <td style="padding: 10px 12px; border-bottom: 1px solid #e5e7eb; color: #6b7280; font-size: 13px;">最もアクティブなユーザー</td>
                    <td style="padding: 10px 12px; border-bottom: 1px solid #e5e7eb; text-align: right; font-weight: bold; color: #111827;">{{ $summary['most_active_user'] }}（{{ $summary['most_active_count'] }} 件）</td>
                </tr>
            </table>
        </div>

        {{-- フッター --}}
        <div style="background-color: #f3f4f6; padding: 16px 20px; text-align: center;">
            <p style="margin: 0; color: #9ca3af; font-size: 12px;">
                このメールはAWS ECSデプロイ練習アプリから自動送信されました。
            </p>
        </div>
    </div>
</body>

</html>