SELECT
    rev,
    TO_TIMESTAMP(revtstmp/1000) AS ts_created
FROM
    datalake_betopera_raw.revinfo
