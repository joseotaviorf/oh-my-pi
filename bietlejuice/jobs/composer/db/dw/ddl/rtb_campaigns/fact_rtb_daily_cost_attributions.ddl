CREATE SCHEMA IF NOT EXISTS rtb_campaigns;

DROP TABLE IF EXISTS rtb_campaigns.fact_rtb_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS rtb_campaigns.fact_rtb_daily_cost_attributions
(
	sk_sub_campaign VARCHAR   ENCODE lzo,
	sk_date INTEGER   ENCODE az64,
	clicks DOUBLE PRECISION   ENCODE RAW,
	impressions DOUBLE PRECISION   ENCODE RAW,
	ctr DOUBLE PRECISION   ENCODE RAW,
	cost DOUBLE PRECISION   ENCODE RAW,
	conversions_count DOUBLE PRECISION   ENCODE RAW,
	conversion_rate DOUBLE PRECISION   ENCODE RAW,
	cpc DOUBLE PRECISION   ENCODE RAW,
	ts_load TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
)
DISTSTYLE AUTO
;
ALTER TABLE rtb_campaigns.fact_rtb_daily_cost_attributions owner to databricks;

CALL grant_all_permissions_on_schema('rtb_campaigns');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA rtb_campaigns TO GROUP etl;
GRANT ALL ON SCHEMA rtb_campaigns TO GROUP ETL;