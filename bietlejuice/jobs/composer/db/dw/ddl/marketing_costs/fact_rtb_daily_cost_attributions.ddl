DROP TABLE IF EXISTS marketing_costs.fact_rtb_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_rtb_daily_cost_attributions (
    sk_sub_campaign VARCHAR PRIMARY KEY,
    sk_date INTEGER,
    clicks DOUBLE PRECISION,
    impressions DOUBLE PRECISION,
    ctr DOUBLE PRECISION,
    cost DOUBLE PRECISION,
    conversions_count DOUBLE PRECISION,
    conversions_rate DOUBLE PRECISION,
    cpc DOUBLE PRECISION,
    ts_load TIMESTAMP
);
ALTER TABLE marketing_costs.fact_rtb_daily_cost_attributions OWNER TO airflow;