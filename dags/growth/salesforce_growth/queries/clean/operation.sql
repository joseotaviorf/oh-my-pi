SELECT
    Id AS id,
    Name AS name,
    dt_updated,
    year,
    month,
    day
FROM
    datalake_salesforce_growth_raw.operation
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')