import React, { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import apiClient from '../lib/api';

// 認証モード: 'password' のときはメール+パスワードフォーム、それ以外（既定）は Google ログイン。
// preview 環境では VITE_AUTH_MODE=password を渡してパスワードログインを使う。
const AUTH_MODE = import.meta.env.VITE_AUTH_MODE ?? 'google';

const Login: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user, login } = useAuth();
  const hasCleanedError = useRef(false);

  // パスワードログイン用の状態
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [formError, setFormError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // URLパラメータからエラーメッセージを取得
  const errorParam = searchParams.get('error');
  const error = errorParam ? decodeURIComponent(errorParam) : null;

  // 既にログインしている場合はダッシュボードへリダイレクト
  useEffect(() => {
    if (user) {
      navigate('/dashboard');
    }
  }, [user, navigate]);

  // URLからエラーパラメータを削除（エラーがある場合のみ、一度だけ実行）
  useEffect(() => {
    if (errorParam && !hasCleanedError.current) {
      hasCleanedError.current = true;
      // URLパラメータを削除（replace: trueで履歴に残さない）
      const newSearchParams = new URLSearchParams(searchParams);
      newSearchParams.delete('error');
      navigate(`/login?${newSearchParams.toString()}`, { replace: true });
    }
  }, [errorParam, searchParams, navigate]);

  // Google認証URLを取得してリダイレクト
  const handleGoogleLogin = async () => {
    try {
      const response = await apiClient.get('/auth/google');
      // バックエンドから返されたGoogle認証URLにリダイレクト
      window.location.href = response.data.url;
    } catch (error) {
      console.error('Googleログインエラー:', error);
      alert('ログインに失敗しました');
    }
  };

  // メール+パスワードでログイン
  const handlePasswordLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);
    setSubmitting(true);
    try {
      const response = await apiClient.post('/auth/login', { email, password });
      // セッションが確立されたのでユーザー状態を更新（useEffect が /dashboard へ遷移）
      login(response.data.user);
    } catch (err) {
      console.error('ログインエラー:', err);
      setFormError('メールアドレスまたはパスワードが正しくありません。');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full space-y-8 p-8 bg-white rounded-lg shadow-md">
        <div>
          <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
            AWS ECSデプロイ練習★
          </h2>
          <p className="mt-2 text-center text-sm text-gray-600">
            {AUTH_MODE === 'password'
              ? 'メールアドレスとパスワードでログインしてください'
              : 'Googleアカウントでログインしてください'}
          </p>
          {error && (
            <div className="mt-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-md text-sm">
              {error}
            </div>
          )}
        </div>

        {AUTH_MODE === 'password' ? (
          <form className="mt-8 space-y-4" onSubmit={handlePasswordLogin}>
            <div>
              <label htmlFor="email" className="block text-sm font-medium text-gray-700">
                メールアドレス
              </label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div>
              <label htmlFor="password" className="block text-sm font-medium text-gray-700">
                パスワード
              </label>
              <input
                id="password"
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            {formError && (
              <div className="p-3 bg-red-50 border border-red-200 text-red-700 rounded-md text-sm">
                {formError}
              </div>
            )}
            <button
              type="submit"
              disabled={submitting}
              className="w-full flex justify-center items-center px-4 py-3 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-60"
            >
              {submitting ? 'ログイン中...' : 'ログイン'}
            </button>
          </form>
        ) : (
          <div className="mt-8">
            <button
              onClick={handleGoogleLogin}
              className="w-full flex justify-center items-center px-4 py-3 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              <svg className="w-5 h-5 mr-2" viewBox="0 0 24 24">
                <path
                  fill="currentColor"
                  d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                />
                <path
                  fill="currentColor"
                  d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                />
                <path
                  fill="currentColor"
                  d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                />
                <path
                  fill="currentColor"
                  d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                />
              </svg>
              Googleでログイン
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default Login;
