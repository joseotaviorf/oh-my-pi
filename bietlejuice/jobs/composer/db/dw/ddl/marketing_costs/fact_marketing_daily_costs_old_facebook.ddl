DROP TABLE IF EXISTS marketing_costs.fact_marketing_daily_costs_old_facebook;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_marketing_daily_costs_old_facebook AS (
    SELECT
        *
    FROM
        marketing_costs.fact_marketing_daily_costs_old
    WHERE
        mkt_source = 'Facebook'
);
ALTER TABLE marketing_costs.fact_marketing_daily_costs_old_facebook OWNER TO airflow;