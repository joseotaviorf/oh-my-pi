DROP TABLE datalake_raw.marketing_rtb_stats;

CREATE EXTERNAL TABLE datalake_raw.marketing_rtb_stats(
  subcampaign string,
  subcampaignHash string,
  day string,
  impscount string,
  clickscount string,
  ctr string,
  campaigncost string,
  conversionscount string,
  cr string,
  cpc string,
  ecps string,
  ecc string,
  roas string,
  conversionsValue string,
  account_name string,
  account_hash string,
  account_status string,
  account_currency string
)
PARTITIONED BY(
  acc string,
  dt string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' WITH SERDEPROPERTIES (
'ignore.malformed.json' = 'true'
)
STORED AS INPUTFORMAT 'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://5a-datalake/raw/marketing/rtb_ads/stats'

MSCK REPAIR TABLE datalake_raw.marketing_rtb_stats;