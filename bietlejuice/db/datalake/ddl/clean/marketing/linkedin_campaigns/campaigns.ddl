DROP TABLE IF EXISTS datalake_clean.marketing_linkedin_campaigns;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_linkedin_campaigns (
    account_name string,
		id_campaign string,
    campaign_name string,
		id_ad string,
		ad_name string,
    currency string,
    daily_budget string,
    account_total_budget string,
    total_spent string,
    impressions string,
    clicks string,
    other_clicks string,
    total_engagements string,
    conversions string,
    cost_per_conversion string,
    cost_per_lead string
) PARTITIONED BY (
  dt_created string
)
STORED AS PARQUET
LOCATION
  's3://5a-datalake/clean/marketing/linkedin_campaigns/marketing_linkedin_campaigns/'

MSCK REPAIR TABLE datalake_clean.marketing_linkedin_campaigns;