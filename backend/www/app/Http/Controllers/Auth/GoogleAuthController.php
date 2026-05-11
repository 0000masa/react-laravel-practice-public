<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;
use Laravel\Socialite\Facades\Socialite;

class GoogleAuthController extends Controller
{
    /**
     * Google認証URLを取得
     * 
     * @return JsonResponse
     */
    public function redirect(): JsonResponse
    {
        // Laravel SocialiteでGoogle認証URLを取得
        // APIルートでセッションが有効になっているため、通常のredirect()を使用
        $redirectResponse = Socialite::driver('google')
            ->redirect();
        
        $url = $redirectResponse->getTargetUrl();

        return response()->json(['url' => $url]);
    }

    /**
     * Google認証コールバック処理
     * セッションベース認証でログインし、フロントエンドにリダイレクト
     * 
     * @param Request $request
     * @return \Illuminate\Http\RedirectResponse
     */
    public function callback(Request $request)
    {
        try {
            // Google認証情報を取得
            // APIルートでセッションが有効になっているため、通常のuser()を使用
            $googleUser = Socialite::driver('google')->user();

            // 既存ユーザーを検索（google_idまたはemailで）
            $user = User::where('google_id', $googleUser->getId())
                ->orWhere('email', $googleUser->getEmail())
                ->first();

            if ($user) {
                // 既存ユーザーの場合、google_idとavatar_urlを更新
                $user->update([
                    'google_id' => $googleUser->getId(),
                    'avatar_url' => $googleUser->getAvatar(),
                    'email_verified_at' => now(),
                ]);
            } else {
                // 新規ユーザーを作成
                $user = User::create([
                    'name' => $googleUser->getName(),
                    'email' => $googleUser->getEmail(),
                    'google_id' => $googleUser->getId(),
                    'avatar_url' => $googleUser->getAvatar(),
                    'email_verified_at' => now(),
                    // Googleログインの場合はパスワード不要
                    'password' => null,
                ]);
            }

            // セッションベース認証でログイン
            Auth::login($user);

            // フロントエンドのURLにリダイレクト（セッションで認証状態を保持）
            // nginx経由でアクセスする場合はhttp://localhost、開発環境では環境変数で上書き可能
            $frontendUrl = env('FRONTEND_URL', 'http://localhost');
            return redirect($frontendUrl . '/auth/callback');
        } catch (\Exception $e) {
            // エラーの詳細をログに記録
            Log::error('Google認証エラー', [
                'message' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            // エラー時もフロントエンドにリダイレクト（デバッグ用にエラーメッセージを含める）
            $frontendUrl = env('FRONTEND_URL', 'http://localhost');
            $errorMessage = config('app.debug') 
                ? $e->getMessage() 
                : '認証に失敗しました';
            return redirect($frontendUrl . '/login?error=' . urlencode($errorMessage));
        }
    }

    /**
     * ログアウト処理
     * 
     * @param Request $request
     * @return JsonResponse
     */
    public function logout(Request $request): JsonResponse
    {
        // セッションからログアウト
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return response()->json(['message' => 'ログアウトしました']);
    }

    /**
     * 認証済みユーザー情報を取得
     * 
     * @param Request $request
     * @return JsonResponse
     */
    public function user(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'avatar_url' => $user->avatar_url,
            ],
        ]);
    }
}

