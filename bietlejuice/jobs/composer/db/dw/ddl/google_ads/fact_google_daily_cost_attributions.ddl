CREATE SCHEMA IF NOT EXISTS marketing_costs;

DROP TABLE IF EXISTS marketing_costs.fact_google_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_google_daily_cost_attributions (
	sk_date BIGINT,
	sk_keyword VARCHAR,
	sk_ad VARCHAR,
	sk_campaign VARCHAR,
	sk_video VARCHAR,
	id_ad BIGINT,
	id_keyword BIGINT,
	id_external_customer BIGINT,
	id_campaign BIGINT,
	id_ad_group VARCHAR,
	mobile_clicks BIGINT,
	tablet_clicks BIGINT,
	computer_clicks BIGINT,
	total_clicks BIGINT,
	mobile_cost FLOAT,
	desktop_cost FLOAT,
	total_cost FLOAT,
	mobile_impressions BIGINT,
	tablet_impressions BIGINT,
	desktop_impressions BIGINT,
	impressions BIGINT,
	ts_load TIMESTAMP
);

ALTER TABLE marketing_costs.fact_google_daily_cost_attributions OWNER TO databricks;

CALL grant_all_permissions_on_schema('marketing_costs');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA marketing_costs TO GROUP etl;
GRANT ALL ON SCHEMA marketing_costs TO GROUP ETL;