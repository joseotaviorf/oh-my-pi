SELECT
    domain,
    platform,
    visits,
    pages_per_visit,
    average_visit_duration,
    bounce_rate,
    unique_visitors,
    date AS dt_traffic,
    YEAR(date) AS year,
    MONTH(date) AS month,
    DAY(date) AS day
FROM
    datalake_similarweb_daily_metrics_raw.traffic
WHERE
    date >= DATE("{week_start_date}")