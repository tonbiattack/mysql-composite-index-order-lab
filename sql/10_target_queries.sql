-- 主対象: user_idとstatusが等価、created_atが範囲、created_at順で最新20件を取得します。
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND created_at >= '2025-10-01 00:00:00'
  AND status = 1
ORDER BY created_at DESC
LIMIT 10000;

-- 対照: 全てのキー部が等価のため、EXPLAINのtype=refとref=const,const,constを確認できます。
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND status = 1
  AND created_at = '2025-10-01 00:00:00';
