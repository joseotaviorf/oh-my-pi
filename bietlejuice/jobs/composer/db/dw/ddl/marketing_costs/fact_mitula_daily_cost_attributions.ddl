DROP TABLE IF EXISTS marketing_costs.fact_mitula_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_mitula_daily_cost_attributions AS (
    sk_mitula_campaign BIGINT,
    sk_date INTEGER,
    clicks INTEGER,
    desktop_cost FLOAT,
    mobile_cost FLOAT,
    total_cost FLOAT,
    ts_load TIMESTAMP
);
ALTER TABLE marketing_costs.fact_mitula_daily_cost_attributions OWNER TO airflow;