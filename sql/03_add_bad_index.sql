-- user_idの等価条件の後にcreated_atの範囲条件が続くため、
-- status=1はインデックス探索範囲を狭めるキー部として使えません。
ALTER TABLE orders
  ADD INDEX idx_orders_user_created_status (user_id, created_at, status);

ANALYZE TABLE orders;
SHOW INDEX FROM orders;
