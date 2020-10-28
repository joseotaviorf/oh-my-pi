DROP TABLE IF EXISTS marketing_costs.fact_criteo_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_criteo_daily_cost_attributions (
    sk_criteo_campaign varchar primary key,
    sk_date int,
    clicks int,
    impressions int,
    audience varchar,
    cost double precision,
    all_sales varchar,
    revenue double precision,
    composition_win double precision,
    cost_per_click double precision,
    ts_load timestamp
);