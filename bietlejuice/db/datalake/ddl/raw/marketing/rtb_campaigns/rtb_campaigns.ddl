DROP TABLE datalake_raw.marketing_criteo_campaigns;

CREATE EXTERNAL TABLE datalake_raw.marketing_criteo_campaigns (
  day string,
  impressions string,
  clicks string,
  ctr string,
  conversions_count string,
  conversions_rate string,
  cpc string,
  ecc string,
  roas string,
  conversions_value
  )
PARTITIONED BY (
  dt_extraction string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json'    = 'true',
'mapping.day'              = 'day',
'mapping.impressions'      = 'impsCount',
'mapping.clicks'           = 'clicksCount',
'mapping.conversions_count'= 'conversionsCount',
'mapping.conversions_rate' = 'conversionsRate',
'mapping.conversions_value'= 'conversionsValue',
)
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/rtb_campaigns/all/'

MSCK REPAIR TABLE datalake_raw.marketing_criteo_campaigns;