WITH get_validations AS (
    SELECT DISTINCT
        t.dag,
        dv.database,
        dv.table,
        dv.suite_result,
        EXPLODE(FROM_JSON(dv.validations, 'ARRAY<STRING>')) AS validations,
        dv.ts_execution_utc,
        dv.ts_execution_local,
        dv.year,
        dv.month,
        dv.day
    FROM
        datalake_inmetro_clean.data_validations AS dv
    INNER JOIN
        datalake_dag_inventory_clean.table AS t
            ON t.table = CONCAT(REPLACE(dv.database, "_staging", ""), ".", dv.table)
    WHERE
        MAKE_DATE(dv.year, dv.month, dv.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
        AND dv.repo = 'bietlejuice'
)
SELECT
    dag AS id_dag,
    database,
    table,
    IF(GET_JSON_OBJECT(validations, "$.column") = '*', 'table', 'column') AS validation_level,
    IF(GET_JSON_OBJECT(validations, "$.column") = '*', 'N/A', GET_JSON_OBJECT(validations, "$.column")) AS column,
    GET_JSON_OBJECT(validations, "$.validation") AS validation_type,
    GET_JSON_OBJECT(validations, "$.result") AS validation_result,
    LOWER(GET_JSON_OBJECT(validations, "$.status")) AS validation_status,
    suite_result AS table_status,
    ts_execution_utc,
    ts_execution_local AS ts_execution_brt,
    year,
    month,
    day
FROM
    get_validations
