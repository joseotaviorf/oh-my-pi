SELECT
    id,
    reference,
    label,
    utmSource as utm_source,
    utmMedium as utm_medium,
    utmCampaign as utm_campaign,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    year,
    month,
    day
FROM
    datalake_quires_raw.plates
WHERE
    DATE(createdAt) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
