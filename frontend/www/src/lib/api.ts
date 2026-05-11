import axios from 'axios';

// APIのベースURL（環境変数から取得、デフォルトはnginx経由の/api）
// 開発環境で直接Laravelにアクセスする場合は環境変数で上書き可能
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api';

// Axiosインスタンスを作成
// セッションベース認証のため、withCredentials: trueでセッションクッキーを送信
const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  },
  withCredentials: true,
});

// レスポンスインターセプター: エラーハンドリング
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // 認証エラーの場合、ログイン画面へリダイレクト（既にログインページまたはコールバックページの場合はリダイレクトしない）
      const currentPath = window.location.pathname;
      if (currentPath !== '/login' && currentPath !== '/auth/callback') {
        window.location.href = '/login';
      }
    }
    return Promise.reject(error);
  }
);

export default apiClient;

