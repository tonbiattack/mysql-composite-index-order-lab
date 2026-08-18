# mysql-composite-index-order-lab

MySQL 8において、「必要なカラムにはINDEXが貼られているのに、クエリが想定ほど速くならない」状況を、複合インデックスの列順に絞って再現・観測するための検証リポジトリです。`(user_id, created_at, status)` と `(user_id, status, created_at)` を同じデータ、同じSQLで比較し、`EXPLAIN` と `EXPLAIN ANALYZE` の両方を記録します。

> 結論は、`=` で固定する `user_id` と `status` を先に置き、範囲検索する `created_at` を最後に置いた `(user_id, status, created_at)` の方が、このクエリでは探索範囲を小さくできる、ということです。複合インデックスは左端プレフィックスを使えますが、実務では「どのキー部までを検索範囲の決定に使えたか」を実行計画で確認します。[1](https://dev.mysql.com/doc/refman/8.4/en/multiple-column-indexes.html)

## 環境構築

Docker Composeが使える環境を前提にします。ホストの3306番ポートは使用しません。コンテナ内部のMySQLへはすべてDocker Compose経由で接続するため、既存のMySQLとポート競合しません。

| 項目 | 検証値 |
|---|---|
| MySQLイメージ | `mysql:8.4` |
| 実測したMySQL | `8.4.11` |
| ストレージエンジン | InnoDB |
| テストデータ | 1,200,000件 |
| 対象ユーザー | `user_id = 4242` |
| 対象集合 | `status = 1` かつ `created_at >= '2025-10-01'` の10,038件 |

次のコマンドで、コンテナの初期化、スキーマ作成、データ投入までを実行します。データ投入は環境により数分かかります。

```bash
git clone https://github.com/tonbiattack/mysql-composite-index-order-lab.git
cd mysql-composite-index-order-lab
make reset
```

Dockerデーモンへの権限がない環境では、検証時だけ次のように実行できます。

```bash
make DOCKER='sudo docker' reset
```

## データ生成

`sql/02_seed.sql` は乱数を使わず、毎回同じ分布を作ります。80万件を10,000ユーザーに分散させた後、`user_id = 4242` に40万件を追加します。これにより、`user_id` 単独では選択性が十分でない条件を作ります。

| データ群 | 件数 | 目的 |
|---|---:|---|
| 通常注文 | 800,000 | 多数ユーザーが存在する通常分布 |
| ホットユーザーの注文 | 400,000 | `user_id = 4242` だけでも多数行に当たる状況 |
| ホットユーザーかつ `status = 1` | 40,000 | 等価条件を追加すると絞り込める状況 |
| 対象SQLの結果 | 10,038 | `created_at` の範囲条件も満たす集合 |

投入後の確認SQLは次のとおりです。

```sql
SELECT
  COUNT(*) AS total_rows,
  SUM(user_id = 4242) AS hot_user_rows,
  SUM(user_id = 4242 AND status = 1) AS hot_user_status_rows,
  SUM(user_id = 4242 AND status = 1 AND created_at >= '2025-10-01') AS target_rows
FROM orders;
```

## 対象SQL

`WHERE` に等価検索と範囲検索を含め、`ORDER BY created_at DESC` を付けます。`LIMIT 10000` にして対象集合の大半を読むことで、列順の差を実測しやすくしています。

```sql
SELECT id, user_id, status, created_at, amount_cents, payload
FROM orders
WHERE user_id = 4242
  AND created_at >= '2025-10-01 00:00:00'
  AND status = 1
ORDER BY created_at DESC
LIMIT 10000;
```

比較用に、すべてを等価条件にした対照SQLも `sql/10_target_queries.sql` に置いています。こちらでは `EXPLAIN` の `type=ref` と `ref=const,const,const` を確認できます。

## INDEX

### 改善前: 範囲条件が先に来る列順

まず、次のインデックスを追加します。

```sql
ALTER TABLE orders
  ADD INDEX idx_orders_user_created_status (user_id, created_at, status);
```

`user_id` は等価条件ですが、次の `created_at` は範囲条件です。この時点でB-treeの連続した探索範囲が決まり、後ろの `status = 1` は探索範囲をさらに狭めるキー部としては使えません。`status` は結果を判定するために残ります。

### 改善後: 等価条件を先に置く列順

次に、インデックスを以下へ置き換えます。

```sql
ALTER TABLE orders
  DROP INDEX idx_orders_user_created_status,
  ADD INDEX idx_orders_user_status_created (user_id, status, created_at);
```

先頭の二つのキー部を等価条件で固定してから、最後の `created_at` に対して範囲を作れます。また、先行キー部が固定されているため、同じインデックスを逆順に読んで `ORDER BY created_at DESC` を満たせます。MySQLのインデックスは、利用可能なインデックスの左端プレフィックスを使って検索やソートを最適化します。[2](https://dev.mysql.com/doc/refman/8.4/en/mysql-indexes.html)

## EXPLAIN結果

各SQLは `sql/20_observe_bad_index.sql` と `sql/21_observe_good_index.sql` にあります。実測した生の出力は `evidence/` に保存しています。

```bash
make bad-index
make observe-bad
make good-index
make observe-good
```

| 観測項目 | 改善前 `(user_id, created_at, status)` | 改善後 `(user_id, status, created_at)` |
|---|---|---|
| `possible_keys` | `idx_orders_user_created_status` | `idx_orders_user_status_created` |
| `key` | `idx_orders_user_created_status` | `idx_orders_user_status_created` |
| `type` | `range` | `range` |
| `key_len` | `14` | `14` |
| 主対象SQLの `ref` | `NULL` | `NULL` |
| `rows`（推定） | 183,600 | 18,902 |
| `filtered`（推定） | 10.00 | 100.00 |
| `Extra` | `Using index condition; Backward index scan` | `Using index condition; Backward index scan; Using MRR` |
| `EXPLAIN ANALYZE` の完了時刻 | 106 ms | 67.1 ms |

改善前の主な行は次のとおりです。

```text
type=range
key=idx_orders_user_created_status
rows=183600
filtered=10.00

Index range scan on orders using idx_orders_user_created_status
  over (user_id = 4242 AND '2025-10-01 00:00:00' <= created_at AND 1 <= status)
  (actual time=0.525..105 rows=10000 loops=1)
```

改善後は探索範囲の記述に `status = 1` が入ります。

```text
type=range
key=idx_orders_user_status_created
rows=18902
filtered=100.00

Index range scan on orders using idx_orders_user_status_created
  over (user_id = 4242 AND status = 1 AND '2025-10-01 00:00:00' <= created_at)
  (actual time=0.350..66.5 rows=10000 loops=1)
```

`EXPLAIN` の `possible_keys` は候補、`key` は実際に選ばれたインデックス、`rows` と `filtered` はオプティマイザの推定です。`ref` はインデックスと比較した定数・列を表します。これらは実行前の見積もりであり、実測値は `EXPLAIN ANALYZE` の `actual time`、`rows`、`loops` で確認します。[3](https://dev.mysql.com/doc/refman/8.4/en/explain-output.html) [4](https://dev.mysql.com/doc/refman/8.4/en/explain.html)

対照SQLでは両ケースで以下の行が得られます。範囲検索の主対象SQLでは `ref=NULL` でも異常ではなく、全キー部が等価の対照SQLで `ref` の意味を確認できます。

```text
type=ref
key=idx_orders_user_status_created
ref=const,const,const
rows=1
filtered=100.00
```

## 改善前後

この一回の実測では、完了時刻が106 msから67.1 msへ変わり、38.9 ms、約36%短縮しました。速度比は約1.57倍です。重要なのは絶対時間の一般化ではなく、同じデータとSQLで、列順を変えるとオプティマイザが推定する探索行数が183,600件から18,902件へ変わり、`EXPLAIN ANALYZE` の実測完了時刻にも差が現れた点です。

| 比較 | 実測値 |
|---|---:|
| 改善前の完了時刻 | 106 ms |
| 改善後の完了時刻 | 67.1 ms |
| 短縮率 | 約36% |
| 速度比 | 約1.57倍 |

## 技術的な考察

「インデックスが使われた」は十分な結論ではありません。改善前も `key` にはインデックス名があり、`type` も `range` です。それでも、`created_at >= ...` が `status` より前にあるため、`status = 1` を探索範囲に組み込めません。実際に `EXPLAIN ANALYZE` の範囲記述は `user_id` と `created_at` を先に示し、`status` は index condition として残ります。

改善後は `user_id = 4242 AND status = 1` を固定してから `created_at >= ...` の範囲を読むため、`status` を含む狭い連続範囲になります。これは単に「左から使われる」という暗記ではなく、対象SQLにおいて、等価条件の後ろに範囲条件を置くと後続キー部が検索範囲の絞り込みに使いにくくなる、という観測です。

ただし、この測定は単一コンテナ、単一接続、温かいキャッシュを含む環境の結果です。実運用ではデータ分布、バッファプール、同時実行、選択列がインデックスを覆うか、書き込み時のインデックス維持コストも変わります。したがって、列順を決める前後で実データの `EXPLAIN` と `EXPLAIN ANALYZE` を取り、推定と実測を両方比較してください。

## 回帰テスト

`tests/assert_composite_index_plan.sh` は、最終状態で次を確認します。

- `orders` が120万件であること
- 対象行が存在すること
- インデックス列順が `user_id,status,created_at` であること
- `EXPLAIN FORMAT=JSON` が修正後の `key` と `range` アクセスを選ぶこと
- 三つのキー部が `used_key_parts` に出ること

```bash
make test
# PASS: rows=1200000, target_rows=10038, key=idx_orders_user_status_created, access=range
```

修正前コミットでは同じテストが、期待するインデックスが存在しないため失敗します。検証記録は [DEBUGGING_RECORD.md](DEBUGGING_RECORD.md) を参照してください。

## ファイル構成

```text
.
├── docker-compose.yml
├── Makefile
├── sql/
│   ├── 01_schema.sql
│   ├── 02_seed.sql
│   ├── 03_add_bad_index.sql
│   ├── 04_replace_with_good_index.sql
│   ├── 10_target_queries.sql
│   ├── 20_observe_bad_index.sql
│   └── 21_observe_good_index.sql
├── evidence/
│   ├── bad_index_plan.txt
│   ├── good_index_plan.txt
│   └── bug_regression_failure.txt
└── tests/
    └── assert_composite_index_plan.sh
```

## 参考資料

1. [MySQL 8.4 Reference Manual: Multiple-Column Indexes](https://dev.mysql.com/doc/refman/8.4/en/multiple-column-indexes.html)
2. [MySQL 8.4 Reference Manual: How MySQL Uses Indexes](https://dev.mysql.com/doc/refman/8.4/en/mysql-indexes.html)
3. [MySQL 8.4 Reference Manual: EXPLAIN Output Format](https://dev.mysql.com/doc/refman/8.4/en/explain-output.html)
4. [MySQL 8.4 Reference Manual: EXPLAIN Statement](https://dev.mysql.com/doc/refman/8.4/en/explain.html)
