SELECT
    site_url,
    type AS google_property,
    keys[0] AS country,
    keys[1] AS device_category,
    CAST(clicks AS INT) AS clicks,
    CAST(ctr AS DOUBLE) AS ctr,
    CAST(impressions AS INT) AS impressions,
    CAST(position AS DOUBLE) AS position,
    date AS dt_created,
    year(date) AS year,
    month(date) AS month,
    day(date) AS day
FROM
    datalake_google_search_console_raw.url_by_page_without_page
WHERE
    date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')