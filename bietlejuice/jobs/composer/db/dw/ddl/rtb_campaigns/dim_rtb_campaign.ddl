CREATE SCHEMA IF NOT EXISTS rtb_campaigns;

DROP TABLE IF EXISTS rtb_campaigns.dim_rtb_campaign;
CREATE TABLE IF NOT EXISTS rtb_campaigns.dim_rtb_campaign
(
	sk_sub_campaign VARCHAR   ENCODE lzo,
	sk_date INTEGER   ENCODE az64,
	campaign_name VARCHAR(256)   ENCODE lzo,
	account_hash VARCHAR(256)   ENCODE lzo,
	account_name VARCHAR(256)   ENCODE lzo,
	account_currency VARCHAR(256)   ENCODE lzo,
	ts_load TIMESTAMP WITHOUT TIME ZONE   ENCODE az64
)
DISTSTYLE AUTO
;
ALTER TABLE rtb_campaigns.dim_rtb_campaign owner to databricks;

CALL grant_all_permissions_on_schema('rtb_campaigns');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA rtb_campaigns TO GROUP etl;
GRANT ALL ON SCHEMA rtb_campaigns TO GROUP ETL;