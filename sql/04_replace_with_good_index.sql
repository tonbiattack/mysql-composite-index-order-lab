-- 等価条件のuser_idとstatusを先に並べ、最後にcreated_atの範囲条件を置きます。
-- ORDER BY created_at DESCは、先行キー部が等価条件で固定されるためインデックスを逆順走査できます。
ALTER TABLE orders
  DROP INDEX idx_orders_user_created_status,
  ADD INDEX idx_orders_user_status_created (user_id, status, created_at);

ANALYZE TABLE orders;
SHOW INDEX FROM orders;
