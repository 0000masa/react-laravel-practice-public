<?php

namespace App\Providers;

use Illuminate\Support\Facades\Mail;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // staging / preview 環境では、実ユーザーへの誤送信を防ぐため
        // 全メールの宛先(To/Cc/Bcc)を固定アドレスに上書きする。
        $redirectTo = config('mail.preview_redirect_to');
        if ($redirectTo && in_array(config('app.env'), ['staging', 'preview'], true)) {
            Mail::alwaysTo($redirectTo);
        }
    }
}
