<?php

namespace App\Jobs;

use App\Models\QrCode;
use App\Services\QrCodeService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class GenerateQrCodeJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * 最大試行回数
     */
    public int $tries = 3;

    /**
     * @param int $qrCodeId QRコードレコードのID
     * @param string $data QRコードに含めるデータ
     * @param int $userId ユーザーID
     */
    public function __construct(
        public int $qrCodeId,
        public string $data,
        public int $userId,
    ) {
        // キュー名はあえて指定しない（onQueue で上書きしない）。
        // 指定しなければコネクション(sqs)のデフォルトキュー = SQS_QUEUE 環境変数に従う。
        // これによりキュー名の決定はインフラ側に一本化され、環境ごとに正しく振り分けられる:
        //   - stg     : SQS_QUEUE = staging-qrcode-generation
        //   - preview : SQS_QUEUE = <project>-preview-pr<n>-qrcode-generation（PRごとに一意）
        // 以前は APP_ENV から名前を組み立てていたため、APP_ENV=preview が全PR共通になる
        // preview 環境でキュー名がPR番号入りの実キューと一致せず、ジョブが処理されなかった。
    }

    /**
     * ジョブを実行
     */
    public function handle(QrCodeService $qrCodeService): void
    {
        Log::info("QRコード生成ジョブ開始: ID={$this->qrCodeId}");

        $qrCode = QrCode::find($this->qrCodeId);

        if (!$qrCode) {
            Log::warning("QRコードレコードが見つかりません: ID={$this->qrCodeId}");
            return;
        }

        try {
            // QRコードを生成してS3にアップロード
            $fileName = $qrCodeService->generateAndUpload($this->data, $this->userId);

            // DBレコードを更新
            $qrCode->update([
                'file_name' => $fileName,
                'status' => QrCode::STATUS_COMPLETED,
            ]);

            Log::info("QRコード生成ジョブ完了: ID={$this->qrCodeId}, ファイル名={$fileName}");
        } catch (\Throwable $e) {
            Log::error("QRコード生成ジョブ失敗: ID={$this->qrCodeId}, エラー={$e->getMessage()}");

            // ステータスを失敗に更新
            $qrCode->update([
                'status' => QrCode::STATUS_FAILED,
            ]);

            throw $e; // リトライのために再スロー
        }
    }

    /**
     * ジョブが完全に失敗した場合
     */
    public function failed(?\Throwable $exception): void
    {
        Log::error("QRコード生成ジョブが完全に失敗: ID={$this->qrCodeId}", [
            'exception' => $exception?->getMessage(),
        ]);

        $qrCode = QrCode::find($this->qrCodeId);
        if ($qrCode) {
            $qrCode->update([
                'status' => QrCode::STATUS_FAILED,
            ]);
        }
    }
}
