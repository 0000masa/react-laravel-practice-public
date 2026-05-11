import React from 'react';
import { useAuth } from '../hooks/useAuth';
import Layout from '../components/Layout';
import UserList from '../components/UserList';

const Dashboard: React.FC = () => {
  const { user } = useAuth();

  return (
    <Layout>
      {/* ウェルカムメッセージ */}
      <div className="bg-white shadow rounded-lg p-6">
        <h2 className="text-2xl font-bold text-gray-900 mb-4">ダッシュボード</h2>
        <p className="text-gray-600">
          ようこそ、{user?.name}さん！
        </p>
        <p className="text-gray-600 mt-2">
          このアプリはAWS ECSへのデプロイ練習用です。
        </p>
      </div>

      {/* ユーザー一覧 */}
      <UserList />
    </Layout>
  );
};

export default Dashboard;
