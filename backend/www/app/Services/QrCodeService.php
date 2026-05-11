<?php

namespace App\Services;

use Illuminate\Support\Facades\Storage;
use SimpleSoftwareIO\QrCode\Facades\QrCode;

class QrCodeService
{
    /**
     * QRコードを生成してストレージにアップロード
     * 環境変数STORAGE_DISKに基づいてMinIOまたはS3を使用
     * 
     * @param string $data QRコードに含めるデータ
     * @param int $userId ユーザーID
     * @return string 保存したファイル名（フルパス）
     */
    public function generateAndUpload(string $data, int $userId): string
    {

        try {
            // QRコードを生成（PNG形式）
            $qrCode = QrCode::format('png')
                ->size(300)
                ->generate($data);

            // ファイル名を生成（ユーザーID + タイムスタンプ）
            $fileName = $userId . '_' . time() . '_' . uniqid() . '.png';

            // ストレージにアップロード（MinIOまたはS3）
            Storage::put($fileName, $qrCode);

            return $fileName;
        } catch (\Throwable $e) {
            // 例外を包んで呼び出し元へ再送出
            throw new \RuntimeException('QRコードのアップロードに失敗しました。', 0, $e);
        }
    }
}



