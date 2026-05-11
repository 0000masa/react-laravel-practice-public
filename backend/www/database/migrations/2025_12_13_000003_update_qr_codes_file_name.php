<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     * `s3_url`カラムを`file_name`カラムへ移行し、ファイル名のみを保存する
     */
    public function up(): void
    {
        Schema::table('qr_codes', function (Blueprint $table) {
            // `s3_url`が存在する場合のみ削除し、`file_name`を追加する
            if (Schema::hasColumn('qr_codes', 's3_url')) {
                $table->dropColumn('s3_url');
            }

            if (! Schema::hasColumn('qr_codes', 'file_name')) {
                $table->string('file_name')->after('user_id');
            }
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('qr_codes', function (Blueprint $table) {
            if (Schema::hasColumn('qr_codes', 'file_name')) {
                $table->dropColumn('file_name');
            }

            if (! Schema::hasColumn('qr_codes', 's3_url')) {
                $table->string('s3_url')->after('user_id');
            }
        });
    }
};









