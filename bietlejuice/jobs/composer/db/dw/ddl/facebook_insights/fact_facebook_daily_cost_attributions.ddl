CREATE SCHEMA IF NOT EXISTS facebook_insights;

DROP TABLE IF EXISTS facebook_insights.fact_facebook_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS facebook_insights.fact_facebook_daily_cost_attributions (
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
ALTER TABLE facebook_insights.fact_facebook_daily_cost_attributions OWNER TO databricks;

CALL grant_all_permissions_on_schema('facebook_insights');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA facebook_insights TO GROUP etl;
GRANT ALL ON SCHEMA facebook_insights TO GROUP ETL;