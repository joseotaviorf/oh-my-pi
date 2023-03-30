SELECT
    DispositionId AS id_disposition,
    Description AS description,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.Disposition
WHERE
    DATE('{year}-{month}-{day}') BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')