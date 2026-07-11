<?php

namespace Database\Seeders;

use App\Models\Category;
use Illuminate\Database\Seeder;

/**
 * 投稿の区分マスタ（DB性能学習用）。
 * 10 種 = 100万件時に 1 区分約 10 万件の「低選択性」を作る。
 * マスタの正はこのファイル。bench:seed からも呼ばれる（単一の情報源）。
 */
class CategorySeeder extends Seeder
{
    /** カテゴリ名の正 */
    public const NAMES = ['お知らせ', '日記', '技術', 'ニュース', 'レビュー', '質問', '雑談', 'イベント', '募集', 'その他'];

    public function run(): void
    {
        // 再シードしても重複しないよう updateOrCreate で冪等に
        foreach (self::NAMES as $name) {
            Category::updateOrCreate(['name' => $name]);
        }
    }
}
