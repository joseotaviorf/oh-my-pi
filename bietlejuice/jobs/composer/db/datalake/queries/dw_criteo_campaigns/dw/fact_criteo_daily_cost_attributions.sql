SELECT
    CONCAT(id_campaign, '-', campaign_name) AS sk_criteo_campaign,
    CAST(CONCAT(STRING(year), LPAD(STRING(month),2,'0'), LPAD(STRING(day),2,'0')) AS INTEGER) AS sk_date,
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
    CURRENT_TIMESTAMP AS ts_load
FROM
    datalake_marketing_costs_clean.criteo_campaigns
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}