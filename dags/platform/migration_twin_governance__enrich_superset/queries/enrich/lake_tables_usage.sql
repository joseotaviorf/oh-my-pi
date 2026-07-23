WITH base AS (
  SELECT DISTINCT   -- Using distinct because a lake table may be used several times in a same query
    id AS id_dataset,
    table_name AS dataset_name,
    EXPLODE(REGEXP_EXTRACT_ALL(REPLACE(sql_code, '"', ''), '((datalake_|dw_|metric_)\\w+\\.\\w+)')) AS possible_lake_table,
    ts_created,
    ts_changed,
    year,
    month,
    day
  FROM 
    datalake_superset_clean.tables
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
)
SELECT DISTINCT
    b.id_dataset,
    b.possible_lake_table AS id_lake_table,
    b.dataset_name,
    b.ts_created,
    b.ts_changed,
    b.year,
    b.month,
    b.day
FROM
    base AS b
JOIN
    datalake_dag_inventory_clean.table AS t   -- Inner join to assure that what we found on the regex is a lake table
        ON b.possible_lake_table = t.table
        AND MAKE_DATE(b.year, b.month, b.day) = MAKE_DATE(t.year, t.month, t.day)