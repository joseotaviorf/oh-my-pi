SELECT
    CallDirectionId AS id_call_direction,
    Description AS description,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.Info_CallDirection
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')