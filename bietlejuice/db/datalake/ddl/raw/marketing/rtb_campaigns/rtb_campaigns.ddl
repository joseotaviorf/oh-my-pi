DROP TABLE datalake_raw.marketing_rtb_campaigns;

CREATE EXTERNAL TABLE datalake_raw.marketing_rtb_campaigns (
    status string,
    hash string,
    name string,
    currency string,
    url string,
    day string,
    impscount string,
    clickscount string,
    ctr string,
    campaigncost string,
    conversionscount string,
    conversionsrate string,
    cpc string
)
PARTITIONED BY (
  acc string,
  dt string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
'ignore.malformed.json'   = 'true'
)
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/rtb_campaigns/'

MSCK REPAIR TABLE datalake_raw.marketing_rtb_campaigns;