SELECT 
    rev,
    DATE(TO_TIMESTAMP(CAST(revtstmp/1000 AS BIGINT))) AS dt
FROM 
    revinfo
WHERE
    DATE(TO_TIMESTAMP(CAST(revtstmp/1000 AS BIGINT))) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')