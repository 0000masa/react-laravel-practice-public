<?php

namespace App\Http\Controllers;

use App\Models\Category;
use Illuminate\Http\JsonResponse;

/**
 * DB性能学習用: 投稿一覧UIのカテゴリ絞り込みプルダウン向けに区分マスタを返す。
 */
class CategoryController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json([
            'categories' => Category::select('id', 'name')->orderBy('id')->get(),
        ]);
    }
}
