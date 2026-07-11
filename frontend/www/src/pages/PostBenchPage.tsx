import React, { useEffect, useState } from 'react';
import apiClient from '../lib/api';
import Layout from '../components/Layout';

// DB性能学習用ページ。GET /api/posts をパラメータ違いで叩き、
// 所要時間と EXPLAIN（実行計画）を見比べる。設計は docs/db/query-performance-experiment.md。

interface Post {
  id: number;
  user_id: number;
  category_id: number;
  title: string;
  body: string | null;
  created_at: string;
  user: { id: number; name: string; email: string } | null;
  category: { id: number; name: string } | null;
}

interface Pagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
  from: number | null;
  to: number | null;
}

interface ExplainRow {
  id: number;
  select_type: string;
  table: string | null;
  type: string | null;
  possible_keys: string | null;
  key: string | null;
  key_len: string | null;
  ref: string | null;
  rows: number | null;
  Extra: string | null;
}

interface Category {
  id: number;
  name: string;
}

type MatchMode = 'partial' | 'prefix';

// 5つの検証プリセット（押すと各入力欄へ代表値をセット）
interface Preset {
  label: string;
  hint: string;
  values: {
    userId: string;
    categoryId: string;
    page: string;
    q: string;
    match: MatchMode;
  };
}

const PRESETS: Preset[] = [
  {
    label: '基準: user_id で絞る',
    hint: 'WHERE user_id=? … index が効く（速い）',
    values: { userId: '5', categoryId: '', page: '1', q: '', match: 'partial' },
  },
  {
    label: '深いOFFSET',
    hint: 'LIMIT 50 OFFSET 999950 … index があっても遅い',
    values: { userId: '', categoryId: '', page: '20000', q: '', match: 'partial' },
  },
  {
    label: '部分一致LIKE',
    hint: "title LIKE '%NEEDLE%' … 先頭%で全走査（遅い）",
    values: { userId: '', categoryId: '', page: '1', q: 'NEEDLE', match: 'partial' },
  },
  {
    label: '前方一致LIKE',
    hint: "title LIKE 'NEEDLE%' … index の範囲スキャン（速い・件数は少）",
    values: { userId: '', categoryId: '', page: '1', q: 'NEEDLE', match: 'prefix' },
  },
  {
    label: 'カテゴリ絞り込み',
    hint: 'WHERE category_id=? … 低選択性で index 無視されがち',
    values: { userId: '', categoryId: '1', page: '1', q: '', match: 'partial' },
  },
];

const inputClass =
  'w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500';
const labelClass = 'block text-sm font-medium text-gray-700 mb-1';

const PostBenchPage: React.FC = () => {
  // フォームの状態
  const [userId, setUserId] = useState<string>('');
  const [categoryId, setCategoryId] = useState<string>('');
  const [page, setPage] = useState<string>('1');
  const [q, setQ] = useState<string>('');
  const [match, setMatch] = useState<MatchMode>('partial');
  const [explain, setExplain] = useState<boolean>(true);

  // 結果の状態
  const [categories, setCategories] = useState<Category[]>([]);
  const [posts, setPosts] = useState<Post[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [elapsedMs, setElapsedMs] = useState<number | null>(null);
  const [sql, setSql] = useState<string | null>(null);
  const [explainRows, setExplainRows] = useState<ExplainRow[] | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // カテゴリのプルダウン用データを初回に取得
  useEffect(() => {
    apiClient
      .get('/categories')
      .then((res) => setCategories(res.data.categories))
      .catch((err) => console.error('カテゴリ取得に失敗:', err));
  }, []);

  const applyPreset = (preset: Preset) => {
    setUserId(preset.values.userId);
    setCategoryId(preset.values.categoryId);
    setPage(preset.values.page);
    setQ(preset.values.q);
    setMatch(preset.values.match);
  };

  // クエリ実行。ページング操作では nextPage を渡して上書きする。
  const runQuery = async (nextPage?: number) => {
    const effectivePage = nextPage ?? (Number(page) || 1);
    if (nextPage !== undefined) {
      setPage(String(nextPage));
    }

    const params: Record<string, string | number> = { page: effectivePage };
    if (userId) params.user_id = userId;
    if (categoryId) params.category_id = categoryId;
    if (q) {
      params.q = q;
      params.match = match;
    }
    if (explain) params.explain = 1;

    try {
      setLoading(true);
      setError(null);
      const res = await apiClient.get('/posts', { params });
      setPosts(res.data.posts);
      setPagination(res.data.pagination);
      setElapsedMs(res.data.elapsed_ms ?? null);
      setSql(res.data.sql ?? null);
      setExplainRows(res.data.explain ?? null);
    } catch (err) {
      console.error('投稿の取得に失敗しました:', err);
      setError('投稿の取得に失敗しました');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Layout>
      {/* 操作パネル */}
      <div className="bg-white shadow rounded-lg p-6">
        <h3 className="text-lg font-medium text-gray-900 mb-1">DB検証 (posts)</h3>
        <p className="text-sm text-gray-500 mb-4">
          index が効く/効かないクエリを叩き比べる学習用ページ。レコードは{' '}
          <code className="text-xs bg-gray-100 px-1 rounded">php artisan bench:seed --count=N</code>{' '}
          で投入する。
        </p>

        {/* プリセット */}
        <div className="mb-4">
          <p className={labelClass}>プリセット</p>
          <div className="flex flex-wrap gap-2">
            {PRESETS.map((preset) => (
              <button
                key={preset.label}
                type="button"
                title={preset.hint}
                onClick={() => applyPreset(preset)}
                className="px-3 py-1.5 text-sm rounded-md border border-blue-300 text-blue-700 bg-blue-50 hover:bg-blue-100"
              >
                {preset.label}
              </button>
            ))}
          </div>
        </div>

        {/* 入力欄 */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <div>
            <label className={labelClass}>user_id（数値・任意）</label>
            <input
              type="number"
              value={userId}
              onChange={(e) => setUserId(e.target.value)}
              placeholder="例: 5"
              className={inputClass}
            />
          </div>

          <div>
            <label className={labelClass}>category_id（プルダウン・任意）</label>
            <select
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              className={inputClass}
            >
              <option value="">（指定なし）</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.id}: {c.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className={labelClass}>page（数値・深いOFFSET用）</label>
            <input
              type="number"
              value={page}
              onChange={(e) => setPage(e.target.value)}
              placeholder="例: 20000"
              className={inputClass}
            />
          </div>

          <div>
            <label className={labelClass}>q（title 検索・任意）</label>
            <input
              type="text"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="例: NEEDLE"
              className={inputClass}
            />
          </div>

          <div>
            <label className={labelClass}>match（q 指定時）</label>
            <select
              value={match}
              onChange={(e) => setMatch(e.target.value as MatchMode)}
              className={inputClass}
            >
              <option value="partial">partial（%q% 中間一致・遅い）</option>
              <option value="prefix">prefix（q% 前方一致・速い）</option>
            </select>
          </div>

          <div className="flex items-end">
            <label className="flex items-center gap-2 text-sm font-medium text-gray-700">
              <input
                type="checkbox"
                checked={explain}
                onChange={(e) => setExplain(e.target.checked)}
                className="h-4 w-4"
              />
              explain=1（elapsed_ms と EXPLAIN を表示）
            </label>
          </div>
        </div>

        <button
          type="button"
          onClick={() => runQuery()}
          disabled={loading}
          className="mt-4 px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed"
        >
          {loading ? '実行中...' : '実行'}
        </button>

        {error && (
          <div className="mt-4 bg-red-50 text-red-700 px-4 py-3 rounded-md text-sm">{error}</div>
        )}
      </div>

      {/* メトリクスパネル */}
      {(elapsedMs !== null || sql) && (
        <div className="bg-white shadow rounded-lg p-6">
          <h3 className="text-lg font-medium text-gray-900 mb-4">計測結果</h3>
          <div className="flex flex-wrap gap-6 mb-4">
            <div>
              <p className="text-xs text-gray-500 uppercase">サーバ側SQL時間</p>
              <p className="text-2xl font-semibold text-gray-900">
                {elapsedMs !== null ? `${elapsedMs} ms` : '-'}
              </p>
            </div>
            <div>
              <p className="text-xs text-gray-500 uppercase">総件数 (total)</p>
              <p className="text-2xl font-semibold text-gray-900">
                {pagination ? pagination.total.toLocaleString() : '-'}
              </p>
            </div>
          </div>

          {sql && (
            <div className="mb-4">
              <p className="text-xs text-gray-500 uppercase mb-1">実行SQL</p>
              <pre className="text-xs bg-gray-900 text-gray-100 p-3 rounded-md overflow-x-auto">
                {sql}
              </pre>
            </div>
          )}

          {explainRows && explainRows.length > 0 && (
            <div className="overflow-x-auto">
              <p className="text-xs text-gray-500 uppercase mb-1">EXPLAIN（実行計画）</p>
              <table className="min-w-full divide-y divide-gray-200 text-xs">
                <thead className="bg-gray-50">
                  <tr>
                    {['table', 'type', 'possible_keys', 'key', 'rows', 'Extra'].map((h) => (
                      <th key={h} className="px-3 py-2 text-left font-medium text-gray-500">
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {explainRows.map((row) => (
                    <tr key={row.id}>
                      <td className="px-3 py-2">{row.table ?? '-'}</td>
                      {/* type=ALL / Extra=Using filesort は「遅い」サイン */}
                      <td
                        className={`px-3 py-2 font-medium ${
                          row.type === 'ALL' ? 'text-red-600' : 'text-green-700'
                        }`}
                      >
                        {row.type ?? '-'}
                      </td>
                      <td className="px-3 py-2">{row.possible_keys ?? '-'}</td>
                      <td className="px-3 py-2">{row.key ?? '(未使用)'}</td>
                      <td className="px-3 py-2">{row.rows?.toLocaleString() ?? '-'}</td>
                      <td className="px-3 py-2">{row.Extra ?? '-'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <p className="text-xs text-gray-500 mt-2">
                目安: <span className="text-red-600 font-medium">type=ALL</span> や{' '}
                <span className="text-red-600 font-medium">Using filesort</span> は全走査・全ソートで遅い。
                <span className="text-green-700 font-medium"> type=ref/range</span> は index が効いている。
              </p>
            </div>
          )}
        </div>
      )}

      {/* 一覧テーブル */}
      <div className="bg-white shadow rounded-lg p-6">
        <h3 className="text-lg font-medium text-gray-900 mb-4">投稿一覧</h3>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                {['ID', 'user', 'category', 'title'].map((h) => (
                  <th
                    key={h}
                    className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider"
                  >
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {posts.length === 0 ? (
                <tr>
                  <td colSpan={4} className="px-6 py-4 text-center text-gray-500">
                    データがありません（「実行」を押してください）
                  </td>
                </tr>
              ) : (
                posts.map((post) => (
                  <tr key={post.id}>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{post.id}</td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {post.user?.name ?? `#${post.user_id}`}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {post.category?.name ?? `#${post.category_id}`}
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-900">{post.title}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {pagination && pagination.total > 0 && (
          <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-sm text-gray-600">
              {pagination.from ?? 0} - {pagination.to ?? 0} / {pagination.total.toLocaleString()} 件
            </p>
            <div className="flex items-center gap-2">
              <button
                type="button"
                className="px-3 py-1 text-sm rounded border border-gray-300 text-gray-700 disabled:opacity-50"
                onClick={() => runQuery(pagination.current_page - 1)}
                disabled={pagination.current_page <= 1 || loading}
              >
                前へ
              </button>
              <span className="text-sm text-gray-700">
                {pagination.current_page} / {pagination.last_page} ページ
              </span>
              <button
                type="button"
                className="px-3 py-1 text-sm rounded border border-gray-300 text-gray-700 disabled:opacity-50"
                onClick={() => runQuery(pagination.current_page + 1)}
                disabled={pagination.current_page >= pagination.last_page || loading}
              >
                次へ
              </button>
            </div>
          </div>
        )}
      </div>
    </Layout>
  );
};

export default PostBenchPage;
