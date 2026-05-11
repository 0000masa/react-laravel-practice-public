import React from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';

const Layout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const navigate = useNavigate();
  const { user, logout } = useAuth();

  const handleLogout = async () => {
    await logout();
    navigate('/login');
  };

  const navLinkClass = ({ isActive }: { isActive: boolean }) =>
    `px-3 py-2 text-sm font-medium rounded-md ${
      isActive
        ? 'bg-gray-100 text-gray-900'
        : 'text-gray-600 hover:text-gray-900 hover:bg-gray-50'
    }`;

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between h-16">
            <div className="flex items-center space-x-4">
              <h1 className="text-xl font-semibold text-gray-900">
                AWS ECSデプロイ練習
              </h1>
              <div className="flex items-center space-x-2">
                <NavLink to="/dashboard" className={navLinkClass}>
                  ダッシュボード
                </NavLink>
                <NavLink to="/qrcodes" className={navLinkClass}>
                  QRコード
                </NavLink>
                <NavLink to="/mail" className={navLinkClass}>
                  メール送信
                </NavLink>
              </div>
            </div>
            <div className="flex items-center space-x-4">
              {user && (
                <div className="flex items-center space-x-3">
                  {user.avatar_url && (
                    <img
                      src={user.avatar_url}
                      alt={user.name}
                      className="h-8 w-8 rounded-full"
                    />
                  )}
                  <span className="text-sm text-gray-700">{user.name}</span>
                  <button
                    onClick={handleLogout}
                    className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700"
                  >
                    ログアウト
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      </nav>

      <main className="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <div className="px-4 py-6 sm:px-0 space-y-6">
          {children}
        </div>
      </main>
    </div>
  );
};

export default Layout;
