DROP TABLE if EXISTS staging.fact_rtb_daily_cost_attributions;
CREATE TABLE if NOT EXISTS staging.fact_rtb_daily_cost_attributions (
    sk_sub_campaign varchar,
    sk_date INTEGER,
    currency VARCHAR(100),
    clicks INTEGER,
    impressions DOUBLE PRECISION,
    ctr DOUBLE PRECISION,
    cost DOUBLE PRECISION,
    conversions_count DOUBLE PRECISION,
    conversions_rate DOUBLE PRECISION,
    cpc DOUBLE PRECISION,
    ts_load timestamp
);