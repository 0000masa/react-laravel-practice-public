<?php

namespace App\Http\Controllers;

use App\Models\QrCode;
use App\Services\QrCodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\Storage;

class QrCodeController extends Controller
{
    protected QrCodeService $qrCodeService;

    public function __construct(QrCodeService $qrCodeService)
    {
        $this->qrCodeService = $qrCodeService;
    }

    /**
     * QRコード一覧を取得
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function index(): JsonResponse
    {
        $paginator = QrCode::with('user')
            ->orderBy('created_at', 'desc')
            ->paginate(50);

        $qrcodes = collect($paginator->items())->map(function (QrCode $qrCode) {
            // 環境ごとにURLを生成して返却
            $url = $this->buildQrCodeUrl($qrCode->file_name);

            return [
                'id' => $qrCode->id,
                'user_id' => $qrCode->user_id,
                'user' => $qrCode->user ? [
                    'id' => $qrCode->user->id,
                    'name' => $qrCode->user->name,
                    'email' => $qrCode->user->email,
                ] : null,
                'file_name' => $qrCode->file_name,
                'url' => $url,
                'data' => $qrCode->data,
                'created_at' => $qrCode->created_at,
                'updated_at' => $qrCode->updated_at,
            ];
        })->values();

        return response()->json([
            'qrcodes' => $qrcodes,
            'pagination' => [
                'current_page' => $paginator->currentPage(),
                'last_page' => $paginator->lastPage(),
                'per_page' => $paginator->perPage(),
                'total' => $paginator->total(),
                'from' => $paginator->firstItem(),
                'to' => $paginator->lastItem(),
            ],
        ]);
    }

    /**
     * QRコードを生成してS3にアップロード
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

            // QRコードを生成してS3にアップロード
            $fileName = $this->qrCodeService->generateAndUpload($data, $user->id);

            // データベースに保存
            $qrcode = QrCode::create([
                'user_id' => $user->id,
                'file_name' => $fileName,
                'data' => $data,
            ]);

            return response()->json([
                'message' => 'QRコードを生成しました',
                'qrcode' => array_merge(
                    $qrcode->toArray(),
                    ['url' => $this->buildQrCodeUrl($fileName)]
                ),
            ], 201);
        } catch (\Exception $e) {
            return response()->json([
                'error' => 'QRコードの生成に失敗しました',
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * 環境に応じてQRコードのURLを生成
     */
    private function buildQrCodeUrl(string $fileName): string
    {
        return Storage::url($fileName);
    }
}
