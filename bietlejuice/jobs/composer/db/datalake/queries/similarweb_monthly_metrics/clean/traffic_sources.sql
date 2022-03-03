SELECT
    main_domain AS domain,
    platform,
    source_type,
    domain_share,
    share,
    desktopweb_visits,
    mobileweb_visits,
    date AS dt_traffic,
    YEAR(date) AS year,
    MONTH(date) AS month
FROM
    datalake_similarweb_monthly_metrics_raw.traffic_sources
WHERE
    date = DATE('{previous_month}')