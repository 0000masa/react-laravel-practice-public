<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     * DB性能学習用の投稿テーブル。index が効く/効かないクエリの対比に使う。
     * 設計意図は docs/db/query-performance-experiment.md を参照。
     */
    public function up(): void
    {
        Schema::create('posts', function (Blueprint $table) {
            $table->id();
            // FK（constrained が user_id / category_id に自動で index を張る）
            $table->foreignId('user_id')->constrained()->onDelete('cascade');
            $table->foreignId('category_id')->constrained()->onDelete('cascade');
            // title には「あえて index を張る」。前方一致 LIKE 'x%' では効き、
            // 中間一致 LIKE '%x%' では使われない、という対比を見せるため。
            $table->string('title');
            // body は index なし。1行のサイズを稼いで 100万件の I/O・容量を realistic にする。
            $table->text('body')->nullable();
            $table->timestamps();

            $table->index('title');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('posts');
    }
};
