WITH granularity_ids AS (
    SELECT
        dbu.id_cluster,
        IF(
          LOWER(dbu.cluster_name) LIKE "%bietlejuice%" AND dbu.cluster_name NOT LIKE "% %", 
          REPLACE(
            REPLACE(
              REGEXP_REPLACE(
                REGEXP_REPLACE(dbu.cluster_name, '.+-bietlejuice', 'bietlejuice'), '(?:_mediator|_scheduled|_manual).+', ''
              ), '-', '.'
            ), '_None', ''
          ), 
          NULL
        ) AS id_dag,
        get_json_object(dbu.tags, '$.JobId') AS id_job,
        dbu.cluster_name,
        get_json_object(dbu.tags, '$.RunName') AS job_name,
        dbu.dbus,
        CASE 
          WHEN DATE(dbu.ts_execution) BETWEEN DATE("2022-02-22") AND DATE("2023-08-31") THEN
            CASE
              WHEN dbu.cluster_compute_type = "PREMIUM_ALL_PURPOSE_COMPUTE_(PHOTON)" OR dbu.cluster_compute_type = "PREMIUM_ALL_PURPOSE_COMPUTE" THEN "INTERACTIVE"
              WHEN dbu.cluster_compute_type = "PREMIUM_JOBS_COMPUTE_(PHOTON)" THEN "JOBLIGHT"
              WHEN dbu.cluster_compute_type = "PREMIUM_JOBS_COMPUTE" THEN "AUTOMATED"
              WHEN dbu.cluster_compute_type = "PREMIUM_SQL_COMPUTE" OR dbu.cluster_compute_type = "PREMIUM_SQL_PRO_COMPUTE_US_EAST_N_VIRGINIA" THEN "SQLCOMPUTE"
            END
          ELSE dbu.cluster_compute_type
        END AS cluster_compute_type,
        dbu.ts_execution,
        dbu.year,
        dbu.month,
        dbu.day
    FROM
        datalake_databricks_usage_clean.billable_usage AS dbu
    WHERE
        MAKE_DATE(dbu.year, dbu.month, dbu.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
daily_cluster AS (
    SELECT 
        * 
    FROM 
        datalake_databricks.daily_clusters
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY id_cluster ORDER BY dt_cluster_run DESC) = 1
)
SELECT
    gi.id_cluster,
    gi.id_dag,
    gi.id_job,
    gi.cluster_name,
    gi.job_name,
    gi.cluster_compute_type,
    CASE 
      WHEN gi.id_dag IS NOT NULL THEN "bietlejuice"
      WHEN gi.id_job IS NOT NULL AND gi.id_dag IS NULL THEN "job"
      WHEN LOWER(gi.cluster_name) LIKE "%wonka%" OR LOWER(gi.job_name) LIKE "wonka" AND gi.id_dag IS NOT NULL THEN "wonka dag"
      WHEN LOWER(gi.cluster_name) LIKE "%wonka%" OR LOWER(gi.job_name) LIKE "wonka" AND gi.id_dag IS NULL THEN "wonka job"
      ELSE "adhoc execution"
    END AS execution_context,
    dc.spark_version,
    dc.runtime_engine,
    ROUND(gi.dbus, 2) AS dbus,
    ROUND(gi.dbus * dcd.dbu_price, 2) AS price,
    COUNT(gi.ts_execution) OVER (PARTITION BY COALESCE(gi.id_dag, gi.id_job), date(gi.ts_execution)) AS daily_executions,
    CAST(SPLIT_PART(dc.spark_version, '.', 1) AS INTEGER) AS spark_version_number,
    IF(id_dag IS NOT NULL AND id_job IS NOT NULL, TRUE, FALSE) AS is_dag_builder_migrated,
    DATE(gi.ts_execution) AS dt_execution,
    MIN(DATE(gi.ts_execution)) OVER (PARTITION BY spark_version) AS dt_spark_updated,
    IF(gi.id_dag IS NOT NULL, MIN(gi.ts_execution) OVER (PARTITION BY gi.id_dag ORDER BY gi.ts_execution DESC), NULL) AS ts_bietlejuice_first_execution,
    IF(gi.id_dag IS NOT NULL, MAX(gi.ts_execution) OVER (PARTITION BY gi.id_dag ORDER BY gi.ts_execution DESC), NULL) AS ts_bietlejuice_last_execution,
    IF(gi.id_job IS NOT NULL, MIN(gi.ts_execution) OVER (PARTITION BY gi.id_job ORDER BY gi.ts_execution DESC), NULL) AS ts_job_first_execution,
    IF(gi.id_job IS NOT NULL, MAX(gi.ts_execution) OVER (PARTITION BY gi.id_job ORDER BY gi.ts_execution DESC), NULL) AS ts_job_last_execution,
    gi.ts_execution,
    gi.year,
    gi.month,
    gi.day
FROM
  granularity_ids AS gi
LEFT JOIN
  datalake_gsheets_clean.databricks_contract_details AS dcd
    ON gi.cluster_compute_type = dcd.cluster_compute_type
LEFT JOIN
  daily_cluster AS dc
    ON gi.id_cluster = dc.id_cluster
