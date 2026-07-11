<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // preview 環境のパスワードログイン用テストユーザー。
        // 既存環境で再シードしても重複しないよう updateOrCreate を使う。
        // 認証情報: test@example.com / password
        User::updateOrCreate(
            ['email' => 'test@example.com'],
            [
                'name' => 'Test User',
                'password' => Hash::make('password'),
                'email_verified_at' => now(),
            ]
        );

        // DB性能学習用の区分マスタ（冪等）
        $this->call(CategorySeeder::class);
    }
}
