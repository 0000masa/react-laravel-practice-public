import React, { useEffect, useState } from 'react';
import apiClient from '../lib/api';

interface User {
  id: number;
  name: string;
  email: string;
  avatar_url: string | null;
  created_at: string;
}

interface Pagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
  from: number | null;
  to: number | null;
}

const UserList: React.FC = () => {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [pagination, setPagination] = useState<Pagination | null>(null);

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        setLoading(true);
        const response = await apiClient.get('/users', {
          params: { page: currentPage },
        });
        setUsers(response.data.users);
        setPagination(response.data.pagination);
        setError(null);
      } catch (err) {
        console.error('ユーザー一覧の取得に失敗しました:', err);
        setError('ユーザー一覧の取得に失敗しました');
      } finally {
        setLoading(false);
      }
    };

    fetchUsers();
  }, [currentPage]);

  if (loading) {
    return (
      <div className="bg-white shadow rounded-lg p-6">
        <h3 className="text-lg font-medium text-gray-900 mb-4">ユーザー一覧</h3>
        <p className="text-gray-600">読み込み中...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-white shadow rounded-lg p-6">
        <h3 className="text-lg font-medium text-gray-900 mb-4">ユーザー一覧</h3>
        <p className="text-red-600">{error}</p>
      </div>
    );
  }

  return (
    <div className="bg-white shadow rounded-lg p-6">
      <h3 className="text-lg font-medium text-gray-900 mb-4">ユーザー一覧</h3>
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                アバター
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                名前
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                メールアドレス
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                登録日時
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {users.length === 0 ? (
              <tr>
                <td colSpan={4} className="px-6 py-4 text-center text-gray-500">
                  ユーザーが存在しません
                </td>
              </tr>
            ) : (
              users.map((user) => (
                <tr key={user.id}>
                  <td className="px-6 py-4 whitespace-nowrap">
                    {user.avatar_url ? (
                      <img
                        src={user.avatar_url}
                        alt={user.name}
                        className="h-10 w-10 rounded-full"
                      />
                    ) : (
                      <div className="h-10 w-10 rounded-full bg-gray-300 flex items-center justify-center">
                        <span className="text-gray-600 text-sm">
                          {user.name.charAt(0).toUpperCase()}
                        </span>
                      </div>
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {user.name}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {user.email}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {new Date(user.created_at).toLocaleString('ja-JP')}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {pagination && pagination.total > 0 && (
        <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-gray-600">
            {pagination.from ?? 0} - {pagination.to ?? 0} / {pagination.total} 件
          </p>
          <div className="flex items-center gap-2">
            <button
              type="button"
              className="px-3 py-1 text-sm rounded border border-gray-300 text-gray-700 disabled:opacity-50"
              onClick={() => setCurrentPage((prev) => prev - 1)}
              disabled={currentPage <= 1}
            >
              前へ
            </button>
            <span className="text-sm text-gray-700">
              {pagination.current_page} / {pagination.last_page} ページ
            </span>
            <button
              type="button"
              className="px-3 py-1 text-sm rounded border border-gray-300 text-gray-700 disabled:opacity-50"
              onClick={() => setCurrentPage((prev) => prev + 1)}
              disabled={currentPage >= pagination.last_page}
            >
              次へ
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default UserList;
