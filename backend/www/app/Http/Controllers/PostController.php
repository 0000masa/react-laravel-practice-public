<?php

namespace App\Http\Controllers;

use App\Models\Post;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * DB性能学習用の投稿一覧 API。
 * クエリパラメータで「index が効く/効かない」5パターンを切り替える。
 * 設計は docs/db/query-performance-experiment.md、理屈は docs/db/indexing.md を参照。
 *
 *   ?user_id=5            WHERE user_id=? ORDER BY id DESC       … index 効く（基準）
 *   ?page=20000           ... LIMIT 50 OFFSET 999950            … 深い OFFSET（効かない）
 *   ?q=NEEDLE             WHERE title LIKE '%NEEDLE%'           … 中間一致 LIKE（効かない）
 *   ?q=NEEDLE&match=prefix WHERE title LIKE 'NEEDLE%'           … 前方一致 LIKE（効く）
 *   ?category_id=5        WHERE category_id=?                   … 低選択性（index 無視されがち）
 *   ?explain=1           上記に elapsed_ms と EXPLAIN を添える（stg での確認用）
 */
class PostController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = Post::query()->with(['user:id,name,email', 'category:id,name']);

        // 絞り込み（指定されたものだけ適用）
        if ($request->filled('user_id')) {
            $query->where('user_id', (int) $request->query('user_id'));
        }
        if ($request->filled('category_id')) {
            $query->where('category_id', (int) $request->query('category_id'));
        }
        if ($request->filled('q')) {
            $q = (string) $request->query('q');
            if ($request->query('match') === 'prefix') {
                // 前方一致: index の範囲スキャンが使える
                $query->where('title', 'like', $q . '%');
            } else {
                // 既定は部分一致: 先頭が % のため index が使えず全走査
                $query->where('title', 'like', '%' . $q . '%');
            }
        }

        // 並び順は created_at ではなく主キー id（追加コストゼロで filesort を避ける）
        $query->orderBy('id', 'desc');

        $explain = $request->boolean('explain');
        $page = max(1, (int) $request->query('page', 1));

        // paginate() は内部で $query を書き換えるので、EXPLAIN 用の本体 SELECT は先に複製して確保する
        $explainQuery = $explain ? (clone $query)->forPage($page, 50) : null;

        // サーバ側の DB 実行時間（COUNT + 本体 SELECT + eager load を含む）
        $start = microtime(true);
        $paginator = $query->paginate(50);
        $elapsedMs = round((microtime(true) - $start) * 1000, 2);

        $response = [
            'posts' => $paginator->items(),
            'pagination' => [
                'current_page' => $paginator->currentPage(),
                'last_page' => $paginator->lastPage(),
                'per_page' => $paginator->perPage(),
                'total' => $paginator->total(),
                'from' => $paginator->firstItem(),
                'to' => $paginator->lastItem(),
            ],
        ];

        if ($explain && $explainQuery !== null) {
            $sql = $explainQuery->toSql();
            $response['elapsed_ms'] = $elapsedMs;
            $response['sql'] = $sql;
            // 実行計画を取得（type / key / rows / Extra を UI で見せる）
            $response['explain'] = DB::select('EXPLAIN ' . $sql, $explainQuery->getBindings());
        }

        return response()->json($response);
    }
}
