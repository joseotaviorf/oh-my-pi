SELECT DISTINCT
    id AS sk_creative,
    id AS id_creative,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_marketing_costs_clean.linkedin_creatives
WHERE
    year = '{year}' AND month = '{month}' AND day = '{day}'