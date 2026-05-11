<?php

namespace App\Http\Controllers;

use App\Mail\TestMail;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Validator;

class MailController extends Controller
{
    /**
     * テストメールを送信
     * 
     * @param Request $request
     * @return JsonResponse
     */
    public function send(Request $request): JsonResponse
    {
        // バリデーション
        $validator = Validator::make($request->all(), [
            'to' => 'required|email',
            'subject' => 'required|string|max:255',
            'message' => 'required|string|max:5000',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'error' => 'バリデーションエラー',
                'messages' => $validator->errors(),
            ], 422);
        }

        try {
            $to = $request->input('to');
            $subject = $request->input('subject');
            $message = $request->input('message');

            // メールを送信
            Mail::to($to)->send(new TestMail($subject, $message));

            return response()->json([
                'message' => 'メールを送信しました',
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'error' => 'メールの送信に失敗しました',
                'message' => $e->getMessage(),
            ], 500);
        }
    }
}



