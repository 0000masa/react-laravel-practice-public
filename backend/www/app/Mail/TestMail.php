<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class TestMail extends Mailable
{
    use Queueable, SerializesModels;

    // ★ここが重要：予約語と被らない名前にする
    public string $mailSubject;
    public string $mailBody;

    /**
     * コントローラーからデータを受け取るコンストラクタ
     */
    public function __construct(string $subject, string $message)
    {
        // 受け取った値を、安全なプロパティ名に保存する
        $this->mailSubject = $subject;
        $this->mailBody = $message;
    }

    /**
     * 件名の設定
     */
    public function envelope(): Envelope
    {
        return new Envelope(
            subject: $this->mailSubject, // プロパティを使用
        );
    }

    /**
     * 本文とビューの設定
     */
    public function content(): Content
    {
        return new Content(
            view: 'emails.test',
            with: [
                'body' => $this->mailBody, // ビュー変数 'body' に渡す
            ],
        );
    }
}