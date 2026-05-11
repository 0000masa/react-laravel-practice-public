import React, { useState } from 'react';
import apiClient from '../lib/api';

const QrCodeAsyncGenerator: React.FC = () => {
  const [data, setData] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!data.trim()) {
      setError('データを入力してください');
      return;
    }

    try {
      setLoading(true);
      setError(null);
      setSuccess(null);

      await apiClient.post('/qrcodes/async', { data });

      setSuccess('QRコードの非同期生成ジョブを投入しました');
      setData('');

      window.dispatchEvent(new Event('qrcode-created'));
    } catch (error) {
      console.error('QRコード非同期生成エラー:', error);
      setError('QRコードの非同期生成に失敗しました');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="bg-white shadow rounded-lg p-6">
      <h3 className="text-lg font-medium text-gray-900 mb-4">QRコード非同期生成</h3>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="qrcode-async-data" className="block text-sm font-medium text-gray-700 mb-2">
            QRコードに含めるデータ
          </label>
          <textarea
            id="qrcode-async-data"
            value={data}
            onChange={(e) => setData(e.target.value)}
            rows={3}
            className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-purple-500 focus:border-purple-500"
            placeholder="例: https://example.com または テキストデータ"
            maxLength={1000}
          />
          <p className="mt-1 text-sm text-gray-500">
            {data.length} / 1000 文字
          </p>
        </div>

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
            {error}
          </div>
        )}

        {success && (
          <div className="bg-green-50 border border-green-200 text-green-700 px-4 py-3 rounded">
            {success}
          </div>
        )}

        <button
          type="submit"
          disabled={loading || !data.trim()}
          className="w-full px-4 py-2 bg-purple-600 text-white rounded-md hover:bg-purple-700 disabled:bg-gray-400 disabled:cursor-not-allowed"
        >
          {loading ? '送信中...' : 'QRコードを非同期生成'}
        </button>
      </form>
    </div>
  );
};

export default QrCodeAsyncGenerator;
