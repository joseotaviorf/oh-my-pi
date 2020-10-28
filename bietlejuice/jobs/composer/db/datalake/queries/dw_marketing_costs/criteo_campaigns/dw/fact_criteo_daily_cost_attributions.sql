SELECT
    id AS sk_criteo_campaign,
    CAST(
      CONCAT(
        string(year),
        lpad(string(month), 2, '0'),
        lpad(string(day), 2, '0')
      )
    AS integer) AS sk_date,
    clicks,
    impressions,
    audience,
    cost,
    all_sales,
    revenue,
    composition_win,
    cost_per_click,
    year,
    month,
    day,
    current_timestamp  AS ts_load
FROM datalake_marketing_costs.criteo_campaigns
WHERE year = '{year}' AND month = '{month}' AND day = '{day}'