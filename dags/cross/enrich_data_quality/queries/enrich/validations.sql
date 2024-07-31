WITH get_validations AS (
    SELECT DISTINCT
        t.dag,
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
    INNER JOIN
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
        IF(validations:column = '*', 'table', 'column') AS validation_level,
        IF(validations:column = '*', 'N/A', GET_JSON_OBJECT(validations, "$.column")) AS column,
        validations:validation AS validation_type,
        DOUBLE(validations:result) AS validation_result,
        LOWER(validations:status) AS validation_status,
        suite_result AS table_status,
        ts_execution_utc,
        ts_execution_local AS ts_execution_brt,
        dt_executed,
        year,
        month,
        day
    FROM
        get_validations AS gv
)
SELECT
    MD5(CONCAT(vf.id_dag, vf.database, vf.table, vf.validation_level, vf.column, vf.validation_type)) AS id_data_quality,
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
    validation_fields AS vf
LEFT JOIN
    datalake_data_quality.validations AS v
        ON v.id_data_quality = MD5(CONCAT(vf.id_dag, vf.database, vf.table, vf.validation_level, vf.column, vf.validation_type))
        AND MAKE_DATE(v.year, v.month, v.day) = DATE_SUB(MAKE_DATE(vf.year, vf.month, vf.day), 1)
