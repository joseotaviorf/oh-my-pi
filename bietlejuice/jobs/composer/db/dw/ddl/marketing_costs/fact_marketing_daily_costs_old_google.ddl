DROP TABLE IF EXISTS marketing_costs.fact_marketing_daily_costs_old_google;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_marketing_daily_costs_old_google AS (
    SELECT
        *
    FROM
        marketing_costs.fact_marketing_daily_costs_old
    WHERE
        mkt_source = 'Google'
);
ALTER TABLE marketing_costs.fact_marketing_daily_costs_old_google OWNER TO airflow;