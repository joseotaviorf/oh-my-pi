SELECT
    rev,
    TO_TIMESTAMP(revtstmp/1000) AS ts_created,
    year,
    month,
    day
FROM
    datalake_betopera_raw.revinfo
