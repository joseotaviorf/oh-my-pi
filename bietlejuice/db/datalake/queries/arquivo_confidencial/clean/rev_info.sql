SELECT
    rev,
    TO_TIMESTAMP(revtstmp/1000) AS ts_created,
    year, 
    month, 
    day 
FROM
    datalake_arquivo_confidencial_raw.revinfo
WHERE 
    year = {year}
    AND month = {month}
    AND day= {day}