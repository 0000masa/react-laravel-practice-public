<?php

namespace App\Console\Commands;

use App\Models\Category;
use App\Models\User;
use Database\Seeders\CategorySeeder;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

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
 *
 * 【重要】このコマンドは stg/prod の runner（composer install --no-dev で
 * ビルドされ Faker が無い）でも動く必要があるため、fake()/factory() は使わず、
 * 単語プールからの自前生成 + バルク INSERT で完結させている。
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

    /** title / body を自前生成するための単語プール（Faker 非依存） */
    private const WORDS = [
        'lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur', 'adipiscing', 'elit',
        'sed', 'eiusmod', 'tempor', 'incididunt', 'labore', 'magna', 'aliqua', 'enim',
        'minim', 'veniam', 'quis', 'nostrud', 'exercitation', 'ullamco', 'laboris',
        'nisi', 'aliquip', 'commodo', 'consequat', 'duis', 'aute', 'irure', 'voluptate',
        'velit', 'esse', 'cillum', 'fugiat', 'nulla', 'pariatur', 'excepteur', 'sint',
        'occaecat', 'cupidatat', 'proident', 'sunt', 'culpa', 'officia', 'deserunt',
        'mollit', 'anim', 'laborum', 'perspiciatis', 'unde', 'omnis', 'natus', 'error',
    ];

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

        $this->info("posts に {$count} 件を追加します（チャンク " . self::CHUNK_SIZE . " 件ずつ）...");
        $remaining = $count;
        $inserted = 0;

        while ($remaining > 0) {
            $batch = min(self::CHUNK_SIZE, $remaining);
            $rows = [];

            for ($i = 0; $i < $batch; $i++) {
                // title は単語プールからランダムに組み立ててバラつかせる
                $title = $this->randomPhrase(4, 8);
                // 一部の行にだけ既知語 NEEDLE を混ぜ、LIKE のヒット件数を制御可能にする
                if (random_int(1, self::NEEDLE_RATE) === 1) {
                    $title .= ' NEEDLE';
                }

                $rows[] = [
                    'user_id' => $userIds[array_rand($userIds)],
                    'category_id' => $categoryIds[array_rand($categoryIds)],
                    'title' => $title,
                    'body' => $this->randomPhrase(20, 40),
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
     * 単語プールから min〜max 語をつないだ文字列を作る（先頭大文字）。
     */
    private function randomPhrase(int $min, int $max): string
    {
        $n = random_int($min, $max);
        $words = [];
        for ($i = 0; $i < $n; $i++) {
            $words[] = self::WORDS[array_rand(self::WORDS)];
        }

        return ucfirst(implode(' ', $words));
    }

    /**
     * users を目標人数まで用意する（不足分だけバルク INSERT で作成）。
     * user_id を 1,000 人に分散させることで WHERE user_id=? が高選択性になる。
     * factory()/fake() は Faker 依存で runner に無いため使わない。
     */
    private function ensureUsers(): void
    {
        $current = User::count();
        if ($current >= self::TARGET_USERS) {
            return;
        }

        $toCreate = self::TARGET_USERS - $current;
        $this->info("users を {$toCreate} 人作成します（目標 " . self::TARGET_USERS . " 人）...");

        // 既存 email と衝突しないよう、現在の最大 id を基準に連番で振る
        $base = (int) (User::max('id') ?? 0);
        // パスワードハッシュは 1 回だけ計算して使い回す（bcrypt を毎回叩かない）
        $password = Hash::make('password');
        $now = now();

        $rows = [];
        for ($i = 1; $i <= $toCreate; $i++) {
            $seq = $base + $i;
            $rows[] = [
                'name' => "Bench User {$seq}",
                'email' => "bench_user_{$seq}@example.test",
                'email_verified_at' => $now,
                'password' => $password,
                'created_at' => $now,
                'updated_at' => $now,
            ];

            if (count($rows) >= self::CHUNK_SIZE) {
                DB::table('users')->insert($rows);
                $rows = [];
            }
        }
        if ($rows !== []) {
            DB::table('users')->insert($rows);
        }
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
