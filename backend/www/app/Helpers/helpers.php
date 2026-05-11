<?php

use App\Services\logging\ExecuteLogService;

/**
 * JSON_UNESCAPED_UNICODE オプションを使用してJSONレスポンスを作成.
 * 
 * 名前衝突を防ぐために if文で制御.
 * 
 * @param mixed $data
 * @param int $status
 * @param array $headers
 * @param int $options
 * @return \Illuminate\Http\JsonResponse
 */
if (!function_exists('jsonResponse')) {
    function jsonResponse($data = null, $status = 200, $headers = [], $options = JSON_UNESCAPED_UNICODE)
    {
        return response()->json($data, $status, $headers, $options);
    }
}

/**
 * 実行ログをログファイルとログテーブルの両方に書き込む処理.
 * ログレベル毎に関数を分けて定義.
 * 
 * @param string $message    （必須）ログ本文
 * @param int    $functionId （必須）実行範囲（システム機能マスタから ID を指定）
 * @param int    $userId     （任意）実行ユーザー（管理ユーザーの ID を指定、デフォルトはシステムユーザー）
 * @param array  $context    （任意）追加の補足情報
 * @return void
 */
if (!function_exists('logDebug')) {
    function logDebug(string $message, int $functionId, int $userId = 1, array $context = []): void
    {
        app(ExecuteLogService::class)->executeLog($message, $functionId, $userId, $context, 'debug');
    }
}
if (!function_exists('logInfo')) {
    function logInfo(string $message, int $functionId, int $userId = 1, array $context = []): void
    {
        app(ExecuteLogService::class)->executeLog($message, $functionId, $userId, $context, 'info');
    }
}
if (!function_exists('logNotice')) {
    function logNotice(string $message, int $functionId, int $userId = 1, array $context = []): void
    {
        app(ExecuteLogService::class)->executeLog($message, $functionId, $userId, $context, 'notice');
    }
}
if (!function_exists('logWarning')) {
    function logWarning(string $message, int $functionId, int $userId = 1, array $context = []): void
    {
        app(ExecuteLogService::class)->executeLog($message, $functionId, $userId, $context, 'warning');
    }
}
if (!function_exists('logError')) {
    function logError(string $message, int $functionId, int $userId = 1, array $context = []): void
    {
        app(ExecuteLogService::class)->executeLog($message, $functionId, $userId, $context, 'error');
    }
}
if (!function_exists('logCritical')) {
    function logCritical(string $message, int $functionId, int $userId = 1, array $context = []): void
    {
        app(ExecuteLogService::class)->executeLog($message, $functionId, $userId, $context, 'critical');
    }
}
