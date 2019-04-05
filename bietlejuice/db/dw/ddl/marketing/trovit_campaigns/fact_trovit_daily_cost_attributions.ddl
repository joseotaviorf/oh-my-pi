DROP TABLE if EXISTS marketing.fact_trovit_daily_cost_attributions;
CREATE TABLE if NOT EXISTS marketing.fact_trovit_daily_cost_attributions (
    sk_trovit_campaign INTEGER,
    sk_date INTEGER,
    clicks INTEGER,
    cost DOUBLE PRECISION,
    ts_load timestamp
);