<?php

namespace App\Console\Commands;

use App\Models\Category;
use App\Models\User;
use Database\Seeders\CategorySeeder;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * DB性能学習用の posts 投入コマンド（追加式）。
 * 使い方は docs/db/query-performance-experiment.md を参照。
 *
 *   php artisan bench:seed --count=10000     # posts に 1万件を「追加」
 *   php artisan bench:seed --count=1000000   # 一気に 100万件を追加
 *   php artisan bench:seed --fresh           # posts を全削除してやり直す
 *
 * GitHub Actions からは db-task.yml の command_type=shell で:
 *   shell_command = php artisan bench:seed --count=1000000
 */
class BenchSeedCommand extends Command
{
    protected $signature = 'bench:seed
        {--count=0 : 追加する posts の件数}
        {--fresh : 投入前に posts を全削除する（users/categories は保持）}';

    protected $description = 'DB性能学習用に posts テーブルへダミー投稿を追加する';

    /** 目標ユーザー数（user_id を適度に分散させ、WHERE user_id=? を高選択性にする） */
    private const TARGET_USERS = 1000;

    /** 1回の INSERT でまとめる行数（メモリ一定・往復削減のバランス） */
    private const CHUNK_SIZE = 2000;

    /** LIKE '%NEEDLE%' のヒットを仕込む割合（約 1/10000 行） */
    private const NEEDLE_RATE = 10000;

    public function handle(): int
    {
        // 大量 INSERT でクエリログにメモリを食わせない
        DB::connection()->disableQueryLog();

        if ($this->option('fresh')) {
            $this->warn('posts を全削除します...');
            DB::table('posts')->truncate();
            $this->info('posts を truncate しました。');
        }

        $this->ensureUsers();
        $this->ensureCategories();

        $count = (int) $this->option('count');
        if ($count <= 0) {
            $this->info('--count が 0 のため投入はスキップしました（users/categories の準備のみ実施）。');
            return self::SUCCESS;
        }

        $userIds = User::pluck('id')->all();
        $categoryIds = Category::pluck('id')->all();
        $now = now();
        $faker = fake();

        $this->info("posts に {$count} 件を追加します（チャンク " . self::CHUNK_SIZE . " 件ずつ）...");
        $remaining = $count;
        $inserted = 0;

        while ($remaining > 0) {
            $batch = min(self::CHUNK_SIZE, $remaining);
            $rows = [];

            for ($i = 0; $i < $batch; $i++) {
                // title は Faker でバラつかせる（実務の投稿に近い多様性）
                $title = $faker->sentence(6);
                // 一部の行にだけ既知語 NEEDLE を混ぜ、LIKE のヒット件数を制御可能にする
                if (random_int(1, self::NEEDLE_RATE) === 1) {
                    $title .= ' NEEDLE';
                }

                $rows[] = [
                    'user_id' => $userIds[array_rand($userIds)],
                    'category_id' => $categoryIds[array_rand($categoryIds)],
                    'title' => $title,
                    'body' => $faker->paragraph(3),
                    'created_at' => $now,
                    'updated_at' => $now,
                ];
            }

            // Eloquent の create() ではなくバルク INSERT（1行ずつのクエリを避ける）
            DB::table('posts')->insert($rows);

            $inserted += $batch;
            $remaining -= $batch;

            if ($inserted % 50000 === 0 || $remaining === 0) {
                $this->info("  {$inserted}/{$count} 追加済み");
            }
        }

        $total = DB::table('posts')->count();
        $this->info("完了: 今回 {$count} 件追加 / posts 総件数 = {$total}");

        return self::SUCCESS;
    }

    /**
     * users を目標人数まで用意する（不足分だけ factory で作成）。
     * user_id を 1,000 人に分散させることで WHERE user_id=? が高選択性になる。
     */
    private function ensureUsers(): void
    {
        $current = User::count();
        if ($current >= self::TARGET_USERS) {
            return;
        }

        $toCreate = self::TARGET_USERS - $current;
        $this->info("users を {$toCreate} 人作成します（目標 " . self::TARGET_USERS . " 人）...");
        // UserFactory はパスワードハッシュを static でメモ化するため 1,000 件でも高速
        User::factory()->count($toCreate)->create();
    }

    /**
     * categories を用意する。マスタの正は CategorySeeder（冪等）なのでそれを呼ぶ。
     * 10 種 = 100万件時に 1 区分約 10 万件の「低選択性」を作り出す。
     */
    private function ensureCategories(): void
    {
        // db:seed を通さず bench:seed 単体で叩いてもマスタが揃うようにする保険
        $this->callSilent('db:seed', ['--class' => CategorySeeder::class, '--force' => true]);
        $this->info('categories を用意しました（CategorySeeder / ' . Category::count() . ' 件）。');
    }
}
