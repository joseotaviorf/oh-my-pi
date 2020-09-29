DROP TABLE if EXISTS marketing.fact_rtb_daily_cost_attributions;
CREATE TABLE if NOT EXISTS marketing.fact_rtb_daily_cost_attributions (
    sk_sub_campaign VARCHAR,
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