SELECT DISTINCT
    validation_status
FROM
    datalake_data_quality.validations
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
