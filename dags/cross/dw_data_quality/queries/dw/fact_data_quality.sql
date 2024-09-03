SELECT
    v.id_data_quality AS sk_data_quality,
    v.id_dag AS sk_dag,
    vl.sk_validation_level,
    vt.sk_validation_type,
    vs.sk_validation_status,
    v.validation_result,
    v.consecutive_failure_days,
    v.dt_executed,
    v.year,
    v.month,
    v.day
FROM
    datalake_data_quality.validations AS v
INNER JOIN
    dw_data_quality.dim_validation_level AS vl
        ON vl.database = v.database
        AND vl.table = v.table
        AND vl.column = v.column
INNER JOIN
    dw_data_quality.dim_validation_type AS vt
        ON vt.validation_type = v.validation_type
INNER JOIN
    dw_data_quality.dim_validation_status AS vs
        ON vs.validation_status = v.validation_status
WHERE
    MAKE_DATE(v.year, v.month, v.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
