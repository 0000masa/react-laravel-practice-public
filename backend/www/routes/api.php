<?php

use App\Http\Controllers\Auth\GoogleAuthController;
use App\Http\Controllers\Auth\PasswordAuthController;
use App\Http\Controllers\MailController;
use App\Http\Controllers\QrCodeController;
use App\Http\Controllers\QrCodeQueueController;
use App\Http\Controllers\UserController;
use Illuminate\Support\Facades\Route;

// 認証関連のルート
Route::prefix('auth')->group(function () {
    // Google認証ルートは AUTH_GOOGLE_ENABLED=false（preview 環境など）で無効化する。
    // preview では承認済みリダイレクト URI を PR ごとに登録できないため。
    if (config('services.google.enabled')) {
        // Google認証URLを取得
        Route::get('/google', [GoogleAuthController::class, 'redirect']);
        // Google認証コールバック
        Route::get('/google/callback', [GoogleAuthController::class, 'callback']);
    }

    // メール+パスワードによるログイン（preview のテストユーザー用。本番でもパスワード保有ユーザーは利用可）
    Route::post('/login', [PasswordAuthController::class, 'login']);

    // 認証済みユーザー情報を取得
    Route::get('/user', [GoogleAuthController::class, 'user'])->middleware('auth:web');
    // ログアウト
    Route::post('/logout', [GoogleAuthController::class, 'logout'])->middleware('auth:web');
});

// ユーザー関連のルート（認証必須）
Route::middleware('auth:web')->group(function () {
    Route::get('/users', [UserController::class, 'index']);

    // QRコード関連のルート（同期）
    Route::get('/qrcodes', [QrCodeController::class, 'index']);
    Route::post('/qrcodes', [QrCodeController::class, 'store']);

    // QRコード関連のルート（非同期・SQSキュー処理）
    Route::post('/qrcodes/async', [QrCodeQueueController::class, 'store']);
    Route::get('/qrcodes/{id}/status', [QrCodeQueueController::class, 'status']);

    // メール送信のルート
    Route::post('/mail/send', [MailController::class, 'send']);
});

//ヘルスチェック用のルート
Route::get('/health', function () {
    return response()->json(['status' => 'ok']);
});

Route::get('/debug-s3', function () {
    return [
        'disk' => config('filesystems.default'),
        'bucket' => config('filesystems.disks.s3.bucket'),
        'region' => config('filesystems.disks.s3.region'),
    ];
});
