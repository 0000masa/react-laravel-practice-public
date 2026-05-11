<?php

namespace App\Console\Commands;

use App\Mail\DailyReportMail;
use App\Models\QrCode;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Mail;

class SendDailyReportCommand extends Command
{
    /**
     * コマンド名と説明
     */
    protected $signature = 'report:daily';
    protected $description = '日次レポートメールを全ユーザーに送信する';

    /**
     * コマンドを実行
     */
    public function handle(): int
    {
        $this->info('日次レポートの生成を開始します...');

        // 前日の期間を算出
        $yesterday = Carbon::yesterday();
        $startOfDay = $yesterday->copy()->startOfDay();
        $endOfDay = $yesterday->copy()->endOfDay();

        $this->info("対象期間: {$startOfDay->toDateTimeString()} 〜 {$endOfDay->toDateTimeString()}");

        // ユーザーごとのQRコード生成数を集計
        $qrCountsByUser = QrCode::whereBetween('created_at', [$startOfDay, $endOfDay])
            ->selectRaw('user_id, COUNT(*) as qr_count')
            ->groupBy('user_id')
            ->pluck('qr_count', 'user_id')
            ->toArray();

        // 全体サマリーを算出
        $totalQrCount = array_sum($qrCountsByUser);
        $activeUserCount = count($qrCountsByUser);
        $totalUserCount = User::count();

        // 最もアクティブなユーザーを特定
        $mostActiveUser = null;
        $mostActiveCount = 0;
        if (!empty($qrCountsByUser)) {
            $mostActiveUserId = array_keys($qrCountsByUser, max($qrCountsByUser))[0];
            $mostActiveUser = User::find($mostActiveUserId);
            $mostActiveCount = $qrCountsByUser[$mostActiveUserId];
        }

        $summary = [
            'report_date' => $yesterday->toDateString(),
            'total_qr_count' => $totalQrCount,
            'active_user_count' => $activeUserCount,
            'total_user_count' => $totalUserCount,
            'most_active_user' => $mostActiveUser?->name ?? 'なし',
            'most_active_count' => $mostActiveCount,
        ];

        $this->info("全体サマリー: QR生成数={$totalQrCount}, アクティブユーザー={$activeUserCount}/{$totalUserCount}");

        // 各ユーザーにメールを送信
        $users = User::all();
        $sentCount = 0;

        foreach ($users as $user) {
            $userQrCount = $qrCountsByUser[$user->id] ?? 0;

            try {
                Mail::to($user->email)->send(new DailyReportMail(
                    userName: $user->name,
                    userQrCount: $userQrCount,
                    summary: $summary,
                ));
                $sentCount++;
                $this->info("  ✓ {$user->name} ({$user->email}) に送信しました");
            } catch (\Exception $e) {
                $this->error("  ✗ {$user->name} ({$user->email}) への送信に失敗: {$e->getMessage()}");
            }
        }

        $this->info("日次レポートの送信が完了しました。送信数: {$sentCount}/{$users->count()}");

        return Command::SUCCESS;
    }
}
