<?php

namespace App\Http\Controllers;

use App\Jobs\GenerateQrCodeJob;
use App\Models\QrCode;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;

class QrCodeQueueController extends Controller
{
    /**
     * QRコードを非同期で生成（SQSキューにジョブを投入）
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function store(Request $request): JsonResponse
    {
        // バリデーション
        $validator = Validator::make($request->all(), [
            'data' => 'required|string|max:1000',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'error' => 'バリデーションエラー',
                'messages' => $validator->errors(),
            ], 422);
        }

        try {
            $user = $request->user();
            $data = $request->input('data');

            // DBに pending ステータスのレコードを作成
            $qrCode = QrCode::create([
                'user_id' => $user->id,
                'file_name' => '',
                'data' => $data,
                'status' => QrCode::STATUS_PENDING,
            ]);

            // SQSキューにジョブを投入
            GenerateQrCodeJob::dispatch(
                qrCodeId: $qrCode->id,
                data: $data,
                userId: $user->id,
            );

            return response()->json([
                'message' => 'QRコード生成ジョブをキューに投入しました',
                'qrcode' => [
                    'id' => $qrCode->id,
                    'status' => $qrCode->status,
                    'data' => $qrCode->data,
                    'created_at' => $qrCode->created_at,
                ],
            ], 202);
        } catch (\Exception $e) {
            return response()->json([
                'error' => 'ジョブの投入に失敗しました',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * QRコードの生成ステータスを確認
     *
     * @param int $id
     * @return JsonResponse
     */
    public function status(int $id): JsonResponse
    {
        $qrCode = QrCode::find($id);

        if (!$qrCode) {
            return response()->json([
                'error' => 'QRコードが見つかりません',
            ], 404);
        }

        $response = [
            'id' => $qrCode->id,
            'status' => $qrCode->status,
            'data' => $qrCode->data,
            'created_at' => $qrCode->created_at,
            'updated_at' => $qrCode->updated_at,
        ];

        // 完了済みの場合はURLも含める
        if ($qrCode->status === QrCode::STATUS_COMPLETED && $qrCode->file_name) {
            $response['url'] = Storage::url($qrCode->file_name);
            $response['file_name'] = $qrCode->file_name;
        }

        return response()->json($response);
    }
}
