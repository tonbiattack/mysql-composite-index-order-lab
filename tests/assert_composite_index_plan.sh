#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

docker_compose() {
  ${DOCKER:-docker} compose "$@"
}

mysql_query() {
  docker_compose exec -T mysql \
    mysql --protocol=TCP -h 127.0.0.1 -uroot -proot -D index_lab \
    --batch --skip-column-names -e "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if ! grep -Fq "$needle" <<<"$haystack"; then
    printf '%s\n' "$haystack" >&2
    fail "$description（期待した断片: $needle）"
  fi
}

row_count="$(mysql_query "SELECT COUNT(*) FROM orders")"
[ "$row_count" -eq 1200000 ] || fail "orders件数が120万件ではありません: $row_count"

target_count="$(mysql_query "SELECT COUNT(*) FROM orders WHERE user_id = 4242 AND status = 1 AND created_at >= '2025-10-01 00:00:00'")"
[ "$target_count" -gt 0 ] || fail "対象行が存在しません"

index_columns="$(mysql_query "SELECT GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ',') FROM information_schema.statistics WHERE table_schema = 'index_lab' AND table_name = 'orders' AND index_name = 'idx_orders_user_status_created'")"
[ "$index_columns" = "user_id,status,created_at" ] || fail "修正後インデックスの列順が不正です: ${index_columns:-<未作成>}"

plan_json="$(mysql_query "EXPLAIN FORMAT=JSON SELECT id, user_id, status, created_at, amount_cents, payload FROM orders WHERE user_id = 4242 AND created_at >= '2025-10-01 00:00:00' AND status = 1 ORDER BY created_at DESC LIMIT 10000")"
assert_contains "$plan_json" '"key": "idx_orders_user_status_created"' "修正後インデックスが選択されていません"
assert_contains "$plan_json" '"access_type": "range"' "範囲アクセスになっていません"
assert_contains "$plan_json" '"used_key_parts": [' "利用キー部が出力されていません"
assert_contains "$plan_json" '"user_id"' "user_idが利用キー部にありません"
assert_contains "$plan_json" '"status"' "statusが利用キー部にありません"
assert_contains "$plan_json" '"created_at"' "created_atが利用キー部にありません"

printf 'PASS: rows=%s, target_rows=%s, key=idx_orders_user_status_created, access=range\n' "$row_count" "$target_count"
