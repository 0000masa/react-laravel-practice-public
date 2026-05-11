import React, { useState } from 'react';
import apiClient from '../lib/api';

const MailSender: React.FC = () => {
  const [to, setTo] = useState<string>('');
  const [subject, setSubject] = useState<string>('');
  const [message, setMessage] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!to.trim() || !subject.trim() || !message.trim()) {
      setError('すべての項目を入力してください');
      return;
    }

    try {
      setLoading(true);
      setError(null);
      setSuccess(null);

      await apiClient.post('/mail/send', {
        to,
        subject,
        message,
      });
      
      setSuccess('メールを送信しました');
      setTo('');
      setSubject('');
      setMessage('');
    } catch (error) {
      console.error('メール送信エラー:', error);
      setError('メールの送信に失敗しました');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="bg-white shadow rounded-lg p-6">
      <h3 className="text-lg font-medium text-gray-900 mb-4">メール送信</h3>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="mail-to" className="block text-sm font-medium text-gray-700 mb-2">
            送信先メールアドレス
          </label>
          <input
            type="email"
            id="mail-to"
            value={to}
            onChange={(e) => setTo(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
            placeholder="example@example.com"
            required
          />
        </div>

        <div>
          <label htmlFor="mail-subject" className="block text-sm font-medium text-gray-700 mb-2">
            件名
          </label>
          <input
            type="text"
            id="mail-subject"
            value={subject}
            onChange={(e) => setSubject(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
            placeholder="メールの件名"
            maxLength={255}
            required
          />
        </div>

        <div>
          <label htmlFor="mail-message" className="block text-sm font-medium text-gray-700 mb-2">
            メッセージ
          </label>
          <textarea
            id="mail-message"
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            rows={5}
            className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
            placeholder="メールの本文"
            maxLength={5000}
            required
          />
          <p className="mt-1 text-sm text-gray-500">
            {message.length} / 5000 文字
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
          disabled={loading || !to.trim() || !subject.trim() || !message.trim()}
          className="w-full px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed"
        >
          {loading ? '送信中...' : 'メールを送信'}
        </button>
      </form>
    </div>
  );
};

export default MailSender;



