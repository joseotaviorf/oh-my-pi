DROP TABLE IF EXISTS datalake_raw.marketing_linkedin_campaigns;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_linkedin_campaigns (
	account_id string,
	campaign_id string,
	campaign_name string,
	creative string,
	date_sk string,
	unique_reach string,
	impressions string,
	freq string,
	cpm string,
	imp_cost_usd string,
	engaje string,
	clicks string,
	ctr string,
	cpc string,
	eng_cost_usd string,
	vd_imps string,
	VD_REACH string,
	VD_engage string,
	vd_unique_3rd_quartile string,
	vd_unique_midpoint string,
	vd_unique_1st_quartile string,
	cpv string
) PARTITIONED BY (
  dt string)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"',
  'skip.header.line.count' = '1'
)
LOCATION
  's3://5a-datalake/raw/marketing/linkedin_campaigns/campaigns'

MSCK REPAIR TABLE datalake_raw.marketing_linkedin_campaigns;