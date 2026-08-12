WITH get_validations AS (
    SELECT DISTINCT
        COALESCE(t.dag, -1) AS dag,
        IF(startswith(dv.database, 'dw_') AND endswith(dv.database, '_staging'), REPLACE(dv.database, "_staging", ""), dv.database) AS database,
        dv.table,
        dv.suite_result,
        EXPLODE(FROM_JSON(dv.validations, 'ARRAY<STRING>')) AS validations,
        dv.ts_execution_utc,
        dv.ts_execution_local,
        DATE(dv.ts_execution_local) AS dt_executed,
        dv.year,
        dv.month,
        dv.day
    FROM
        datalake_inmetro_clean.data_validations AS dv
    LEFT JOIN
        datalake_dag_inventory_clean.table AS t
            ON t.table = CONCAT(IF(startswith(dv.database, 'dw_') AND endswith(dv.database, '_staging'), REPLACE(dv.database, "_staging", ""), dv.database), ".", dv.table)
    WHERE
        MAKE_DATE(dv.year, dv.month, dv.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
        AND dv.repo = 'bietlejuice'
),
validation_fields AS (
    SELECT
        dag AS id_dag,
        database,
        table,
        IF(GET_JSON_OBJECT(validations, '$.column') = '*', 'table', 'column') AS validation_level,
        IF(GET_JSON_OBJECT(validations, '$.column') = '*', 'N/A', GET_JSON_OBJECT(validations, '$.column')) AS column,
        GET_JSON_OBJECT(validations, '$.validation') AS validation_type,
        CAST(GET_JSON_OBJECT(validations, '$.result') AS DOUBLE) AS validation_result,
        LOWER(GET_JSON_OBJECT(validations, '$.status')) AS validation_status,
        suite_result AS table_status,
        ts_execution_utc,
        ts_execution_local AS ts_execution_brt,
        dt_executed,
        year,
        month,
        day
    FROM
        get_validations AS gv
),
validation_keys AS (
    SELECT
        MD5(CONCAT(id_dag, database, table, validation_level, column, validation_type)) AS id_data_quality,
        id_dag,
        database,
        table,
        validation_level,
        column,
        validation_type,
        validation_result,
        validation_status,
        table_status,
        ts_execution_utc,
        ts_execution_brt,
        dt_executed,
        year,
        month,
        day
    FROM
        validation_fields
),
prior_day_validations AS (
    -- Static partition pre-filter so EMR Spark 3.5 prunes to the prior-day
    -- partitions instead of full-scanning the whole output history. The join's
    -- MAKE_DATE(v...) = DATE_SUB(MAKE_DATE(vf...), 1) restriction only ever
    -- matches v dates in [load_start_date - 1, load_end_date - 1], so this
    -- range is exact and the LEFT JOIN result is unchanged.
    SELECT
        id_data_quality,
        consecutive_failure_days,
        year,
        month,
        day
    FROM
        datalake_data_quality.validations
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{load_start_date}'), 1) AND DATE_SUB(DATE('{load_end_date}'), 1)
)
SELECT
    vf.id_data_quality,
    vf.id_dag,
    vf.database,
    vf.table,
    vf.validation_level,
    vf.column,
    vf.validation_type,
    vf.validation_result,
    vf.validation_status,
    vf.table_status,
    IF(vf.validation_status = 'failure', COALESCE(v.consecutive_failure_days, 0) + 1, 0) AS consecutive_failure_days,
    vf.ts_execution_utc,
    vf.ts_execution_brt,
    vf.dt_executed,
    vf.year,
    vf.month,
    vf.day
FROM
    validation_keys AS vf
LEFT JOIN
    prior_day_validations AS v
        ON v.id_data_quality = vf.id_data_quality
        AND MAKE_DATE(v.year, v.month, v.day) = DATE_SUB(MAKE_DATE(vf.year, vf.month, vf.day), 1)
