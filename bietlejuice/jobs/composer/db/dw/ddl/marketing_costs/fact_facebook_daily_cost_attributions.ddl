DROP TABLE IF EXISTS marketing_costs.fact_facebook_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_facebook_daily_cost_attributions (
    sk_date INTEGER,
    sk_ad VARCHAR,
    id_ad BIGINT,
    id_account BIGINT,
    id_campaign BIGINT,
    id_adset BIGINT,
    impressions VARCHAR(512),
    reach VARCHAR(512),
    inline_link_clicks VARCHAR(512),
    spend VARCHAR(512),
    spend_mobile FLOAT,
    spend_desktop FLOAT,
    spend_other FLOAT,
    dt_start DATE,
    dt_stop DATE,
    ts_load TIMESTAMP
);
ALTER TABLE marketing_costs.fact_facebook_daily_cost_attributions OWNER TO airflow;
