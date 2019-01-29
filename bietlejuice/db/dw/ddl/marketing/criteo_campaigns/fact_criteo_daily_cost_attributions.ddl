DROP TABLE if EXISTS marketing.fact_criteo_daily_cost_attributions;
CREATE TABLE if NOT EXISTS marketing.fact_criteo_daily_cost_attributions (
    advertiser_name VARCHAR(65535),
    sk_criteo_campaign INTEGER,
    sk_cost_attribution_date INTEGER,
    currency VARCHAR(65535),
    clicks INTEGER,
    impressions DOUBLE PRECISION,
    audience DOUBLE PRECISION,
    cost DOUBLE PRECISION,
    all_sales INTEGER,
    revenue INTEGER,
    composition_win DOUBLE PRECISION,
    cpc DOUBLE PRECISION,
)
;