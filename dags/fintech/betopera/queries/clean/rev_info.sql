SELECT
    rev,
    TO_TIMESTAMP(revtstmp/1000) AS ts_created,
    year,
    month,
    day
FROM
    datalake_betopera_raw.revinfo
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
