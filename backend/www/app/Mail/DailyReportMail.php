<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class DailyReportMail extends Mailable
{
    use Queueable, SerializesModels;

    /**
     * @param string $userName ユーザー名
     * @param int $userQrCount そのユーザーのQRコード生成数
     * @param array $summary 全体サマリーデータ
     */
    public function __construct(
        public string $userName,
        public int $userQrCount,
        public array $summary,
    ) {}

    /**
     * 件名の設定
     */
    public function envelope(): Envelope
    {
        return new Envelope(
            subject: "【日次レポート】{$this->summary['report_date']} QRコード生成サマリー",
        );
    }

    /**
     * 本文とビューの設定
     */
    public function content(): Content
    {
        return new Content(
            view: 'emails.daily-report',
            with: [
                'userName' => $this->userName,
                'userQrCount' => $this->userQrCount,
                'summary' => $this->summary,
            ],
        );
    }
}
