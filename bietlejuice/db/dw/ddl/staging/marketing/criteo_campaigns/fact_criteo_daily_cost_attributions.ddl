DROP TABLE if EXISTS staging.fact_criteo_daily_cost_attributions;
CREATE TABLE if NOT EXISTS staging.fact_criteo_daily_cost_attributions (
    sk_criteo_campaign INTEGER,
    sk_date INTEGER,
    currency VARCHAR(100),
    clicks INTEGER,
    impressions DOUBLE PRECISION,
    audience DOUBLE PRECISION,
    cost DOUBLE PRECISION,
    all_sales INTEGER,
    revenue INTEGER,
    composition_win DOUBLE PRECISION,
    cpc DOUBLE PRECISION,
    ts_load timestamp
)
;