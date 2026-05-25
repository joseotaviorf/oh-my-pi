# Compatible constructs — work unchanged on Databricks AND EMR Spark 3.5

The linter must **not** flag any of the constructs below. They run identically on Databricks DBR 16.4 (Spark 3.5 + Photon) and on plain EMR Spark 3.5.

This list exists to suppress false-positive noise and to give the rewriter a vocabulary it can lean on when translating away from the critical patterns.

## Conditional / null handling

- `IF(cond, t, f)` — Spark 1.0+
- `CASE WHEN ... THEN ... ELSE ... END` — ANSI
- `COALESCE(a, b, ...)` — ANSI
- `NVL(a, b)` — Spark
- `IFNULL(a, b)` — Spark (alias of NVL)
- `NULLIF(a, b)` — ANSI
- `IS NOT DISTINCT FROM` — Spark 3.0+ (use to mimic `DECODE` NULL-equality semantics)

## Aggregates

- `COUNT_IF(cond)` — Spark 3.0+
- `ANY_VALUE(col)` — Spark 3.4+
- `COLLECT_LIST(col)` / `COLLECT_SET(col)` — Spark
- `APPROX_COUNT_DISTINCT(col)` — Spark
- `PERCENTILE_APPROX(col, p)` — Spark
- `BOOL_AND` / `BOOL_OR` / `EVERY` / `SOME` — Spark 3.0+
- `BIT_AND` / `BIT_OR` / `BIT_XOR` — Spark

## Casts

- `CAST(x AS <type>)` — ANSI
- `TRY_CAST(x AS <type>)` — Spark 3.2+
- `TRY_DIVIDE(a, b)` — Spark 3.4+
- `TRY_TO_TIMESTAMP(x [, fmt])` — Spark 3.4+

## Date / time

- `MAKE_DATE(y, m, d)` — Spark 3.0+
- `MAKE_TIMESTAMP(...)` — Spark 3.0+
- `ADD_MONTHS(date, n)` — Spark
- `DATE_ADD(date, days)` / `DATE_SUB(date, days)` — Spark
- `DATEDIFF(end, start)` — **2-arg form only**; returns days. (3-arg form with unit is critical, see RECIPES §5.)
- `TIMESTAMPDIFF(unit, start, end)` — Spark 3.4+ (use this in place of 3-arg `DATEDIFF`)
- `DATE_TRUNC('unit', ts)` / `TRUNC(date, 'unit')` — Spark
- `DATE_FORMAT(ts, fmt)` — Spark; **safe** patterns include `yyyy`, `MM`, `dd`, `HH`, `mm`, `ss`, `SSS`, `E`, `EEEE`, escaped literals like `'T'`. Pattern letters that changed semantics in Spark 3.0 (`u`, `U`, `L`, `F`, `c`) are flagged with severity `🟡 attention` — see RECIPES §7.
- `EXTRACT(field FROM ts)` — Spark
- `DAYOFWEEK(date)` / `DAYOFYEAR(date)` / `WEEKOFYEAR(date)` — Spark
- `FROM_UTC_TIMESTAMP(ts, tz)` / `TO_UTC_TIMESTAMP(ts, tz)` — Spark
- `UNIX_TIMESTAMP([str, fmt])` / `FROM_UNIXTIME(epoch [, fmt])` — Spark
- `CURRENT_DATE()` / `CURRENT_TIMESTAMP()` — ANSI
- `TIMESTAMP '2026-04-24 00:00:00'` — typed literal, ANSI
- `SEQUENCE(start, stop, step)` — Spark (returns array)

## String

- `CONCAT(a, b, ...)` / `CONCAT_WS(sep, a, b, ...)` — Spark
- `SUBSTRING(str, start, len)` / `SUBSTR(...)` — Spark
- `LENGTH(str)` / `CHAR_LENGTH(str)` — Spark
- `LOWER(str)` / `UPPER(str)` / `INITCAP(str)` — Spark
- `TRIM(str)` / `LTRIM(str)` / `RTRIM(str)` — Spark
- `SPLIT(str, regex [, limit])` — Spark
- `REPLACE(str, search, replace)` — Spark
- `LPAD(str, n, pad)` / `RPAD(str, n, pad)` — Spark
- `INSTR(str, substr)` / `POSITION(substr IN str)` — Spark
- `LIKE` / `ILIKE` (Spark 3.3+) / `RLIKE` — Spark
- `REGEXP_LIKE(str, pat)` — Spark
- `REGEXP_EXTRACT(str, pat, idx)` — Spark
- `REGEXP_REPLACE(str, pat, repl)` — Spark
- `STARTSWITH(str, prefix)` / `ENDSWITH(str, suffix)` — Spark 3.4+
- `OVERLAY(str PLACING repl FROM pos [FOR len])` — Spark 3.0+

## JSON

- `FROM_JSON(json, schema)` — Spark
- `TO_JSON(struct)` — Spark
- `GET_JSON_OBJECT(json, path)` — Spark *(this is the standard rewrite target for variant `:` access)*
- `JSON_TUPLE(json, k1, k2, ...)` — Spark
- `SCHEMA_OF_JSON(json)` — Spark

## Arrays / collections

- `ARRAY(a, b, ...)` — Spark
- `ARRAY_CONTAINS(arr, x)` — Spark
- `SIZE(arr)` / `CARDINALITY(arr)` — Spark
- `ELEMENT_AT(arr, idx)` — Spark
- `EXPLODE(arr)` / `POSEXPLODE(arr)` / `INLINE(arr_of_struct)` — Spark
- `LATERAL VIEW EXPLODE(...)` — Spark / Hive
- `FILTER(arr, x -> cond)` — Spark
- `TRANSFORM(arr, x -> expr)` — Spark
- `AGGREGATE(arr, init, (acc, x) -> expr [, acc -> finish])` — Spark
- `ZIP_WITH(arr1, arr2, (x, y) -> expr)` — Spark
- `EXISTS(arr, x -> cond)` — Spark
- `MAP(k1, v1, k2, v2, ...)` — Spark
- `MAP_FROM_ARRAYS(keys, values)` — Spark
- `MAP_KEYS(map)` / `MAP_VALUES(map)` — Spark
- `STRUCT(a, b, ...)` — Spark

## Math / numeric

- `GREATEST(...)` / `LEAST(...)` — Spark
- `ABS`, `ROUND`, `CEIL`, `FLOOR`, `MOD`, `POWER`, `SQRT`, `EXP`, `LN`, `LOG`, `LOG10`, `LOG2` — Spark
- `RAND()` / `RANDN()` — Spark
- `BIT_LENGTH(str)` — Spark

## Window

- `ROW_NUMBER() OVER (...)` / `RANK() OVER (...)` / `DENSE_RANK() OVER (...)` — ANSI
- `LAG(col, n [, default])` / `LEAD(col, n [, default])` — ANSI
- `FIRST_VALUE` / `LAST_VALUE` — ANSI
- `NTILE(n)` — ANSI
- `SUM/AVG/COUNT/MIN/MAX OVER (...)` — ANSI

## Hashing / encoding

- `SHA2(str, bits)` — Spark
- `MD5(str)` — Spark
- `CRC32(str)` — Spark
- `XXHASH64(...)` — Spark
- `BASE64(bin)` / `UNBASE64(str)` — Spark
- `ENCODE(str, charset)` / `DECODE(bin, charset)` — Spark *(note: `DECODE(bin, charset)` is the **2-arg binary** version — safe. The Oracle-style multi-arg `DECODE(expr, k1, v1, ...)` is the critical one in RECIPES §4.)*
- `HEX(x)` / `UNHEX(str)` — Spark

## Set / table operators

- `UNION` / `UNION ALL` / `INTERSECT` / `EXCEPT` — ANSI
- `CROSS JOIN`, `INNER JOIN`, `LEFT JOIN`, `RIGHT JOIN`, `FULL OUTER JOIN`, `LEFT SEMI JOIN`, `LEFT ANTI JOIN` — Spark / ANSI
- `LATERAL` correlated subqueries — Spark 3.4+
- `VALUES (...)` table constructor — ANSI

## Note on `DECODE`

There are **two** functions named `DECODE` in Spark / Databricks:

- `DECODE(bin, charset)` — **2-arg, binary decoding** (e.g., `DECODE(bytes, 'UTF-8')`). Safe; works on EMR Spark 3.5.
- `DECODE(expr, search, result [, search, result]* [, default])` — **multi-arg, Oracle-style conditional**. Critical; rewrite per RECIPES §4.

The lint regex `\bDECODE\s*\(` matches both. When triaging a finding, count the arguments to decide whether it's safe (binary) or needs rewriting (Oracle-style).
