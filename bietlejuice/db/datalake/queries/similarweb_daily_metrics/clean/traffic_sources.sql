SELECT
    domain,
    platform,
    source_type,
    visits_organic,
    visits_paid,
    pages_per_visit,
    average_duration,
    bounce_rate,
    date AS dt_traffic,
    YEAR(date) AS year,
    MONTH(date) AS month,
    DAY(date) AS day
FROM
    datalake_similarweb_daily_metrics_raw.traffic_sources
WHERE
    date >= DATE("{week_start_date}")