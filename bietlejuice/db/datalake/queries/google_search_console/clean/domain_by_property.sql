SELECT
    site_url,
    type AS google_property,
    keys[0] AS query,
    keys[1] AS country,
    keys[2] AS device_category,
    clicks,
    ctr,
    impressions,
    position,
    date AS dt_created,
    year(date) AS year,
    month(date) AS month,
    day(date) AS day
FROM
    datalake_google_search_console_raw.domain_by_property
WHERE
    date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')