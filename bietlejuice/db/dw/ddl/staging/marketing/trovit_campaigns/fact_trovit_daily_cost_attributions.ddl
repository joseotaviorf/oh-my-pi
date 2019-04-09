DROP TABLE if EXISTS staging.fact_trovit_daily_cost_attributions;
CREATE TABLE if NOT EXISTS staging.fact_trovit_daily_cost_attributions (
    sk_trovit_campaign INTEGER,
    sk_date INTEGER,
    clicks INTEGER,
    cost DOUBLE PRECISION,
    ts_load timestamp
);