DROP TABLE if EXISTS marketing.fact_daily_classifieds_costs;
CREATE TABLE if NOT EXISTS marketing.fact_daily_classifieds_costs (
    sk_classified SMALLINT,
    sk_cost_date BIGINT,
    cost NUMERIC(14,2),
    ts_load timestamp
)
;