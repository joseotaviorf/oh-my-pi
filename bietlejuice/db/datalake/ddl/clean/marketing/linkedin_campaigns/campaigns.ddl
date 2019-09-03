DROP TABLE IF EXISTS datalake_clean.marketing_linkedin_campaigns;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_linkedin_campaigns (
	id_account string,
	id_campaign string,
	campaign_name string,
	impressions string,
	clicks string,
	ctr string,
	cpc string
) PARTITIONED BY (
	acc string,
  dt_created string
)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/linkedin_campaigns/marketing_linkedin_campaigns/'

MSCK REPAIR TABLE datalake_clean.marketing_linkedin_campaigns;