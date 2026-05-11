import React, { useEffect, useState } from 'react';
import apiClient from '../lib/api';

interface QrCodeUser {
  id: number;
  name: string;
  email: string;
}

interface QrCode {
  id: number;
  user_id: number;
  user: QrCodeUser | null;
  file_name: string;
  url: string;
  data: string;
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

const QrCodeList: React.FC = () => {
  const [qrcodes, setQrcodes] = useState<QrCode[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [pagination, setPagination] = useState<Pagination | null>(null);

  const fetchQrcodes = async (page: number) => {
    try {
      setLoading(true);
      const response = await apiClient.get('/qrcodes', {
        params: { page },
      });
      setQrcodes(response.data.qrcodes);
      setPagination(response.data.pagination);
      setError(null);
    } catch (err) {
      console.error('QRコード一覧の取得に失敗しました:', err);
      setError('QRコード一覧の取得に失敗しました');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchQrcodes(currentPage);
  }, [currentPage]);

  useEffect(() => {
    // QRコード生成イベントをリッスン
    const handleQrCodeCreated = () => {
      fetchQrcodes(currentPage);
    };

    window.addEventListener('qrcode-created', handleQrCodeCreated);
    return () => {
      window.removeEventListener('qrcode-created', handleQrCodeCreated);
    };
  }, [currentPage]);

  if (loading) {
    return (
      <div className="bg-white shadow rounded-lg p-6">
        <h3 className="text-lg font-medium text-gray-900 mb-4">QRコード一覧</h3>
        <p className="text-gray-600">読み込み中...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-white shadow rounded-lg p-6">
        <h3 className="text-lg font-medium text-gray-900 mb-4">QRコード一覧</h3>
        <p className="text-red-600">{error}</p>
      </div>
    );
  }

  return (
    <div className="bg-white shadow rounded-lg p-6">
      <h3 className="text-lg font-medium text-gray-900 mb-4">QRコード一覧</h3>
      {qrcodes.length === 0 ? (
        <p className="text-gray-600">QRコードがまだ生成されていません</p>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {qrcodes.map((qrcode) => (
            <div key={qrcode.id} className="border border-gray-200 rounded-lg p-4">
              <div className="mb-2">
                <img
                  src={qrcode.url}
                  alt="QR Code"
                  className="w-full h-auto border border-gray-300 rounded"
                />
              </div>
              <div className="text-sm text-gray-600 mb-2">
                <p className="font-medium">データ:</p>
                <p className="break-words">{qrcode.data}</p>
              </div>
              <div className="text-xs text-gray-500 mb-1">
                作成者: {qrcode.user ? `${qrcode.user.name} (${qrcode.user.email})` : '不明'}
              </div>
              <div className="text-xs text-gray-500">
                作成日時: {new Date(qrcode.created_at).toLocaleString('ja-JP')}
              </div>
              <div className="mt-2">
                <a
                  href={qrcode.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-sm text-blue-600 hover:text-blue-800"
                >
                  S3のURLを開く
                </a>
              </div>
            </div>
          ))}
        </div>
      )}

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

export default QrCodeList;
