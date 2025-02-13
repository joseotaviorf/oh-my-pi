SELECT
    rev,
    TO_TIMESTAMP(CAST(revtstmp/1000 AS BIGINT)) AS dt_rev,
    YEAR(dt_rev) AS year,
    MONTH(dt_rev) AS month,
    DAY(dt_rev) AS day
FROM
    datalake_rene_descartes_raw.revinfo
