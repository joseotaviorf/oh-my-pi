SELECT
    sk_criteo_campaign,
    sk_cost_attribution_date,
    currency,
    clicks,
    impressions,
    audience,
    cost,
    all_sales,
    revenue,
    composition_win,
    cpc,
    getdate() as ts_load
from staging.fact_criteo_daily_cost_attributions