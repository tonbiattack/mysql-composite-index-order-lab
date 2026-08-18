-- 80万件を10,000ユーザーへ均等に配置し、さらにuser_id=4242へ40万件を集中させます。
-- statusは1〜10、created_atは2025年内へ決定的に分散させるため、毎回同じ実行計画を比較できます。

SET @previous_cte_max_recursion_depth = @@SESSION.cte_max_recursion_depth;
SET SESSION cte_max_recursion_depth = 50000;

DELIMITER $$

CREATE PROCEDURE seed_orders()
BEGIN
  DECLARE chunk_offset INT DEFAULT 0;

  WHILE chunk_offset < 800000 DO
    INSERT INTO orders (user_id, status, created_at, amount_cents, payload)
    WITH RECURSIVE sequence_numbers(n) AS (
      SELECT 1
      UNION ALL
      SELECT n + 1 FROM sequence_numbers WHERE n < 50000
    )
    SELECT
      1 + MOD(chunk_offset + n, 10000),
      1 + MOD(chunk_offset + n, 10),
      TIMESTAMP('2025-01-01 00:00:00')
        + INTERVAL MOD((chunk_offset + n) * 37, 31536000) SECOND,
      100 + MOD((chunk_offset + n) * 31, 50000),
      RPAD(CONCAT('base-order-', chunk_offset + n), 512, 'b')
    FROM sequence_numbers;

    SET chunk_offset = chunk_offset + 50000;
  END WHILE;

  SET chunk_offset = 0;
  WHILE chunk_offset < 400000 DO
    INSERT INTO orders (user_id, status, created_at, amount_cents, payload)
    WITH RECURSIVE sequence_numbers(n) AS (
      SELECT 1
      UNION ALL
      SELECT n + 1 FROM sequence_numbers WHERE n < 50000
    )
    SELECT
      4242,
      1 + MOD(chunk_offset + n, 10),
      TIMESTAMP('2025-01-01 00:00:00')
        + INTERVAL MOD((chunk_offset + n) * 7919, 31536000) SECOND,
      100 + MOD((chunk_offset + n) * 97, 50000),
      RPAD(CONCAT('hot-user-order-', chunk_offset + n), 512, 'h')
    FROM sequence_numbers;

    SET chunk_offset = chunk_offset + 50000;
  END WHILE;
END$$

DELIMITER ;

CALL seed_orders();
DROP PROCEDURE seed_orders;
ANALYZE TABLE orders;

SET SESSION cte_max_recursion_depth = @previous_cte_max_recursion_depth;

SELECT
  COUNT(*) AS total_rows,
  SUM(user_id = 4242) AS hot_user_rows,
  SUM(user_id = 4242 AND status = 1) AS hot_user_status_rows,
  SUM(user_id = 4242 AND status = 1 AND created_at >= '2025-10-01') AS target_rows
FROM orders;
