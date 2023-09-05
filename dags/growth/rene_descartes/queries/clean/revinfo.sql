SELECT 
    rev,
    TO_TIMESTAMP(CAST(revtstmp/1000 AS BIGINT)) AS dt_rev,
    year,
    month,
    day
FROM 
    datalake_rene_descartes_raw.revinfo
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY rev ORDER BY revtstmp DESC) = 1    