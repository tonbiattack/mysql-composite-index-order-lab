-- 静的な見積もりを表形式で確認します。
EXPLAIN
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND created_at >= '2025-10-01 00:00:00'
  AND status = 1
ORDER BY created_at DESC
LIMIT 10000;

-- 実際に実行し、actual time、rows、loopsを確認します。
EXPLAIN ANALYZE
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND created_at >= '2025-10-01 00:00:00'
  AND status = 1
ORDER BY created_at DESC
LIMIT 10000;

-- 全キー部が等価の対照クエリです。typeとrefの読み方を確認します。
EXPLAIN
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND status = 1
  AND created_at = '2025-10-01 00:00:00';
