import React, { useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import apiClient from '../lib/api';

const Callback: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { login } = useAuth();

  useEffect(() => {
    const handleCallback = async () => {
      try {
        // URLパラメータからエラーを確認
        const error = searchParams.get('error');

        if (error) {
          alert(decodeURIComponent(error));
          navigate('/login');
          return;
        }

        // セッションで認証状態を確認（バックエンドでAuth::login()が実行済み）
        const response = await apiClient.get('/auth/user');
        
        // ユーザー情報を保存
        login(response.data.user);
        
        // ダッシュボードへリダイレクト
        navigate('/dashboard');
      } catch (error) {
        console.error('コールバック処理エラー:', error);
        navigate('/login');
      }
    };

    handleCallback();
  }, [searchParams, login, navigate]);

  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-center">
        <p className="text-gray-600">認証処理中...</p>
      </div>
    </div>
  );
};

export default Callback;

