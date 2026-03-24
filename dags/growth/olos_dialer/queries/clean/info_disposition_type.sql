SELECT
    DispositionTypeId AS id_disposition_type,
    Description AS description,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.Info_DispositionType
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')