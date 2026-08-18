# 複合インデックス列順のデバッグ記録

## 対象の失敗

`user_id = 4242`、`status = 1`、`created_at >= '2025-10-01'` を条件に、`created_at DESC` で最大10,000件を読むSQLです。`user_id`、`created_at`、`status` のすべてを含む複合インデックスを追加しても、期待したほど探索範囲が小さくならない状態を再現しました。

期待する状態は、`status = 1` を `created_at` の範囲に入る前に検索範囲へ反映し、修正後の複合インデックスが実行計画で選ばれることです。実際の不具合状態では、`(user_id, created_at, status)` が選ばれるものの、`status` は後続キー部であるため主対象SQLの探索範囲を絞り込めませんでした。

## 実行環境と入力

| 項目 | 値 |
|---|---|
| MySQL | 8.4.11 |
| テーブル | `orders` |
| 総件数 | 1,200,000 |
| `user_id = 4242` | 400,080 |
| `user_id = 4242 AND status = 1` | 40,000 |
| 主対象SQLの結果 | 10,038 |

初期化と再現は次の順に行いました。

```bash
make reset
make bad-index
make observe-bad
make test
```

## 観測結果

不利な列順のインデックスは以下です。

```sql
CREATE INDEX idx_orders_user_created_status
  ON orders (user_id, created_at, status);
```

`EXPLAIN` は `key=idx_orders_user_created_status`、`type=range` を示しました。つまり、インデックスが全く使われないわけではありません。しかし、推定 `rows` は183,600、`filtered` は10.00でした。

```text
Index range scan on orders using idx_orders_user_created_status
  over (user_id = 4242 AND '2025-10-01 00:00:00' <= created_at AND 1 <= status)
  (actual time=0.525..105 rows=10000 loops=1)
```

回帰テストは、修正後の列順が存在しないことを理由に意図どおり失敗しました。

```text
FAIL: 修正後インデックスの列順が不正です: NULL
```

この失敗ログは `evidence/bug_regression_failure.txt` に保存しています。

## 原因

主対象SQLでは `user_id` と `status` が等価条件、`created_at` が範囲条件です。`(user_id, created_at, status)` では、`user_id` の次に範囲条件の `created_at` が来るため、その後ろの `status` は連続した検索範囲を決めるキー部として利用できません。`EXPLAIN ANALYZE` の範囲記述に `status` が範囲条件として含まれず、index condition に残ったことが観測根拠です。

MySQLは複合インデックスの左端プレフィックスを検索に利用します。[MySQL 8.4 Reference Manual: Multiple-Column Indexes](https://dev.mysql.com/doc/refman/8.4/en/multiple-column-indexes.html)

## 最小修正

インデックスを次の列順へ置き換えました。

```sql
ALTER TABLE orders
  DROP INDEX idx_orders_user_created_status,
  ADD INDEX idx_orders_user_status_created (user_id, status, created_at);
```

この修正により、`user_id = 4242` と `status = 1` を固定し、その内部で `created_at >= ...` の範囲を読めます。実測では、推定 `rows` が183,600から18,902になり、`EXPLAIN ANALYZE` の完了時刻は106 msから67.1 msになりました。

## 回帰確認

```bash
make good-index
make observe-good
make test
```

最終テスト結果は次のとおりです。

```text
PASS: rows=1200000, target_rows=10038, key=idx_orders_user_status_created, access=range
```

## コミット記録

| 状態 | コミット | 内容 |
|---|---|---|
| バグ再現 | `9d086a7` | 不利なインデックス、実測ログ、失敗する回帰テスト |
| 修正 | `3ccef81` | `user_id, status, created_at` へ列順を変更し、回帰テストを通過 |

## 限界

ここでの時刻は単一コンテナ・単一接続・単一回の測定値です。実運用の絶対値を予測するものではありません。再現可能な比較として、同じデータ、同じSQL、同じコンテナでインデックス列順だけを変え、`EXPLAIN` の推定と `EXPLAIN ANALYZE` の実測を併記しています。
