DROP TABLE IF EXISTS datalake_raw.marketing_linkedin_creatives_stats;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_linkedin_creatives_stats(
  card_clicks                                   string,
  card_impressions                              string,
  clicks                                        string,
  comments                                      string,
  company_page_clicks                           string,
  cost_in_local_currency                        string,
  follows                                       string,
  impressions                                   string,
  likes                                         string,
  opens                                         string,
  pivot_value                                   string,
  reactions                                     string,
  sends                                         string,
  shares                                        string,
  text_url_clicks                               string
)
PARTITIONED BY(
  acc string,
  dt  string
)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES ('ignore.malformed.json' = 'true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/raw/marketing/linkedin_ads/creatives_stats'

MSCK REPAIR TABLE datalake_raw.marketing_linkedin_creatives_stats;