<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     * qr_codesテーブルにstatusカラムを追加（非同期QRコード生成のステータス管理用）
     */
    public function up(): void
    {
        Schema::table('qr_codes', function (Blueprint $table) {
            $table->string('status', 20)->default('completed')->after('data');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('qr_codes', function (Blueprint $table) {
            $table->dropColumn('status');
        });
    }
};
