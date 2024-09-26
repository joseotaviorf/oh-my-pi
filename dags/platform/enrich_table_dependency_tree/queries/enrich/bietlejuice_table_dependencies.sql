WITH table_usage AS (
    SELECT *
    FROM
        datalake_databricks_clean.table_usage_in_queries
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY query_dag_name, query_table_name, query_layer, used_table ORDER BY ts_query_last_modified DESC) = 1
        -- This is because we don't delete old queries from S3 when they are deleted from bietlejuice
        -- If the file hasn't been modified in the last day but some other query was, it means the CI/CD process
        -- ran but that query had been deleted from bietlejuice
        AND ts_query_last_modified > (MAX(ts_query_last_modified) OVER (PARTITION BY year, month, day) - INTERVAL 1 DAYS) 
),
table_inventory AS (
    SELECT *
    FROM
        datalake_dag_inventory_clean.table
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
exact_matches AS (
    SELECT
        tu.query_path,
        tu.used_table,
        ti.`table` AS dependent_table_name,
        ti.dag AS dependent_dag_name,
        ti.task AS dependent_task_name,
        tu.year,
        tu.month,
        tu.day
    FROM
        table_usage AS tu
    JOIN
        table_inventory AS ti
            ON tu.year = ti.year
            AND tu.month = ti.month
            AND tu.day = ti.day
            AND ('bietlejuice.' || tu.query_dag_name) = ti.dag
            AND tu.query_table_name = SPLIT_PART(ti.`table`, '.', 2)
            AND tu.query_layer = ti.layer
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY tu.query_path, tu.used_table ORDER BY ti.task) = 1
),
-- These are for DAGs that don't follow our standard naming pattern, like datamarts or crawlers
fuzzy_matches (
    SELECT
        tu.query_path,
        tu.used_table,
        ti.`table` AS dependent_table_name,
        ti.dag AS dependent_dag_name,
        ti.task AS dependent_task_name,
        tu.year,
        tu.month,
        tu.day
    FROM
        table_usage AS tu
    LEFT JOIN
        exact_matches AS emtu
            ON tu.query_path = emtu.query_path
            AND tu.used_table = emtu.used_table
            AND tu.year = emtu.year
            AND tu.month = emtu.month
            AND tu.day = emtu.day
    JOIN
        table_inventory AS ti
            ON tu.year = ti.year
            AND tu.month = ti.month
            AND tu.day = ti.day
            AND tu.query_table_name = SPLIT_PART(ti.`table`, '.', 2)
            AND tu.query_layer = ti.layer
    LEFT JOIN
        exact_matches AS emti
            ON ti.`table` = emti.dependent_table_name
            AND ti.year = emti.year
            AND ti.month = emti.month
            AND ti.day = emti.day
    WHERE
        emtu.used_table IS NULL
        AND emti.dependent_table_name IS NULL
)
SELECT
    dependent_dag_name,
    dependent_task_name,
    dependent_table_name,
    used_table AS dependency_table_name,
    year,
    month,
    day
FROM
    exact_matches
UNION ALL
SELECT
    dependent_dag_name,
    dependent_task_name,
    dependent_table_name,
    used_table AS dependency_table_name,
    year,
    month,
    day
FROM
    fuzzy_matches
