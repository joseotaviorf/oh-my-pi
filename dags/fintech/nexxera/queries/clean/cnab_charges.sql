SELECT 
    record_type,
    metadata as description,
    TO_TIMESTAMP(CONCAT(year, '-', month, '-', day)) AS ts_ingested,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.cnab_charges
WHERE
    year = {year}
AND 
    month = {month}
AND 
    day = {day}