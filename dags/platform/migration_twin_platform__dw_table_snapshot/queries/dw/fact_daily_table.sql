SELECT
    MD5(table_name || MAKE_DATE(COALESCE(ltc.year, tu.year), COALESCE(ltc.month, tu.month), COALESCE(ltc.day, tu.day))) AS sk_snapshot,
    table_name AS sk_table,
    pd.id_line AS sk_line,
    COALESCE(ltc.dag_name, dit.dag) AS sk_dag,
    CAST(DATE_FORMAT(MAKE_DATE(COALESCE(ltc.year, tu.year), COALESCE(ltc.month, tu.month), COALESCE(ltc.day, tu.day)), 'yyyyMMdd') AS BIGINT) AS sk_snapshot_date,
    COALESCE(ltc.individual_table_cost, 0) AS direct_cost,
    COALESCE(ltc.accumulated_table_dbu_cost, 0) AS total_accumulated_cost,
    COALESCE(tu.individual_usage, 0) AS direct_usage,
    COALESCE(tu.accumulated_usage, 0) AS total_accumulated_usage_count,
    COALESCE(ltc.year, tu.year) AS year, 
    COALESCE(ltc.month, tu.month) AS month, 
    COALESCE(ltc.day, tu.day) AS day
FROM 
    datalake_databricks.load_table_costs AS ltc
FULL OUTER JOIN
    datalake_trino_table_usage.total_table_usage_information AS tu
        USING(table_name, year, month, day)
JOIN
    datalake_dag_inventory_clean.table AS dit
        ON table_name = dit.table
        AND COALESCE(ltc.year, tu.year) = dit.year
        AND COALESCE(ltc.month, tu.month) = dit.month
        AND COALESCE(ltc.day, tu.day) = dit.day
JOIN
    datalake_airflow.dag AS cd
        ON cd.id_dag = dit.dag
JOIN
    datalake_pipeline.dag AS pd
        ON pd.id_dag = COALESCE(ltc.dag_name, dit.dag)
WHERE
    MAKE_DATE(COALESCE(ltc.year, tu.year), COALESCE(ltc.month, tu.month), COALESCE(ltc.day, tu.day))
    BETWEEN '{load_start_date}' AND '{load_end_date}'
QUALIFY
    ROW_NUMBER() OVER(
        PARTITION BY
            COALESCE(ltc.table_name, tu.table_name),
            COALESCE(ltc.year, tu.year),
            COALESCE(ltc.month, tu.month),
            COALESCE(ltc.day, tu.day)
        ORDER BY
            cd.ts_last_scheduler_ran DESC
    ) = 1