-- 不利な列順と完全に同じSQLで、静的見積もりを比較します。
EXPLAIN
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND created_at >= '2025-10-01 00:00:00'
  AND status = 1
ORDER BY created_at DESC
LIMIT 10000;

-- 実行してactual time、実測rows、loopsを比較します。
EXPLAIN ANALYZE
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND created_at >= '2025-10-01 00:00:00'
  AND status = 1
ORDER BY created_at DESC
LIMIT 10000;

-- 対照クエリでは、三つの等価条件がrefに現れることを確認します。
EXPLAIN
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND status = 1
  AND created_at = '2025-10-01 00:00:00';
