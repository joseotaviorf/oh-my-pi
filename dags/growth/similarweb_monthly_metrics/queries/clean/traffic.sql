SELECT
    main_domain AS domain,
    platform,
    desktop_visit_share,
    mobile_web_visit_share,
    date AS dt_traffic,
    YEAR(date) as year,
    MONTH(date) as month
FROM
    datalake_similarweb_monthly_metrics_raw.traffic
WHERE
    date = DATE('{previous_month}')