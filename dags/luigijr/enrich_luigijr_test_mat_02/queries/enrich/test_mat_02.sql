-- ============================================================
-- Diff de inventário de DAGs entre as duas últimas partições (forno_valid)
-- Fonte: datalake_dag_inventory_clean.dag (self-join)
-- Objetivo: comparar a partição diária mais recente com a anterior
--           e classificar cada DAG como added / removed / moved / unchanged.
-- Dialeto: Spark SQL (Databricks). Sem hive., sem funções Trino.
-- ============================================================
WITH dated AS (
    SELECT
        dag,
        dag_location,
        to_date(
            concat_ws('-',
                CAST(`year`  AS STRING),
                lpad(CAST(`month` AS STRING), 2, '0'),
                lpad(CAST(`day`   AS STRING), 2, '0')),
            'yyyy-MM-dd') AS reference_date
    FROM datalake_dag_inventory_clean.dag
),
ranked_days AS (
    -- ranqueia as datas distintas: 1 = mais recente, 2 = anterior
    SELECT
        reference_date,
        DENSE_RANK() OVER (ORDER BY reference_date DESC) AS day_rank
    FROM (SELECT DISTINCT reference_date FROM dated)
),
current_snapshot AS (
    SELECT d.dag, d.dag_location, d.reference_date
    FROM dated d
    JOIN ranked_days r ON d.reference_date = r.reference_date
    WHERE r.day_rank = 1
),
previous_snapshot AS (
    SELECT d.dag, d.dag_location, d.reference_date
    FROM dated d
    JOIN ranked_days r ON d.reference_date = r.reference_date
    WHERE r.day_rank = 2
)
SELECT
    COALESCE(c.dag, p.dag)                       AS dag_name,
    COALESCE(c.dag_location, p.dag_location)     AS dag_location,
    c.reference_date                             AS current_date_ref,
    p.reference_date                             AS previous_date_ref,
    -- classificação da mudança entre as duas partições
    CASE
        WHEN p.dag IS NULL                       THEN 'added'
        WHEN c.dag IS NULL                       THEN 'removed'
        WHEN c.dag_location <> p.dag_location    THEN 'moved'
        ELSE 'unchanged'
    END                                          AS change_status
FROM current_snapshot c
FULL OUTER JOIN previous_snapshot p
    ON c.dag = p.dag
-- só o que efetivamente mudou entre as duas partições
WHERE p.dag IS NULL
   OR c.dag IS NULL
   OR c.dag_location <> p.dag_location
