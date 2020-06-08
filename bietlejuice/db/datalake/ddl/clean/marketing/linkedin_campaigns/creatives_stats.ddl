DROP TABLE IF EXISTS datalake_clean.marketing_linkedin_creatives_stats;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_linkedin_creatives_stats(
  id_creative                                   string,
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
  reactions                                     string,
  sends                                         string,
  shares                                        string,
  text_url_clicks                               string
  )
PARTITIONED BY (
  acc        string,
  dt_created string
)
STORED AS PARQUET LOCATION
's3://5a-datalake/clean/marketing/linkedin_ads/marketing_linkedin_creatives_stats/'

MSCK REPAIR TABLE datalake_clean.marketing_linkedin_creatives_stats;
