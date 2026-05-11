<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     * usersテーブルにGoogle OAuth用のカラムを追加
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // Google IDを保存するカラム（nullable: 通常のパスワード認証ユーザーも存在するため）
            $table->string('google_id')->nullable()->unique()->after('email');
            // アバター画像のURLを保存するカラム
            $table->string('avatar_url')->nullable()->after('google_id');
            // パスワードをnullableに変更（Googleログインの場合はパスワード不要）
            $table->string('password')->nullable()->change();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['google_id', 'avatar_url']);
            $table->string('password')->nullable(false)->change();
        });
    }
};

