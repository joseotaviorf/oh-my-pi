DROP TABLE if EXISTS marketing.fact_classified_daily_cost_attributions;
CREATE TABLE if NOT EXISTS marketing.fact_classified_daily_cost_attributions (
    sk_classified VARCHAR(100),
    sk_date BIGINT,
    funnel_side varchar(10),
    cost NUMERIC(14,2),
    ts_load timestamp
);