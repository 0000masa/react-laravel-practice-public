<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// 日次レポートメール送信（ローカル開発用。本番ではEventBridgeでスケジュール管理）
Schedule::command('report:daily')->dailyAt('11:15');

// テスト用（確認したら dailyAt に戻す）
// Schedule::command('report:daily')->everyMinute();
