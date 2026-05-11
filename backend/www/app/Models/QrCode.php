<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class QrCode extends Model
{
    use HasFactory;

    /**
     * ステータス定数
     */
    public const STATUS_PENDING = 'pending';
    public const STATUS_COMPLETED = 'completed';
    public const STATUS_FAILED = 'failed';

    /**
     * 一括代入可能な属性
     *
     * @var array<int, string>
     */
    protected $fillable = [
        'user_id',
        'file_name',
        'data',
        'status',
    ];

    /**
     * ユーザーとのリレーション
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
