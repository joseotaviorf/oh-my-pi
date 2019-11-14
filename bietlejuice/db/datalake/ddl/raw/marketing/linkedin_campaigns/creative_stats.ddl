DROP TABLE IF EXISTS datalake_raw.marketing_linkedin_creatives_stats;

CREATE EXTERNAL TABLE IF NOT EXISTS datalake_raw.marketing_linkedin_creatives_stats(
  pivot                                         string,
  pivot_value                                   string,
  pivot_values                                  array <string>,
  cost_in_local_currency                        string,
  cost_in_usd                                   string,
  external_website_post_click_conversions       string,
  ad_unit_clicks                                string,
  company_page_clicks                           string,
  one_click_leads                               string,
  text_url_clicks                               string,
  card_clicks                                   string,
  likes                                         string,
  impressions                                   string,
  card_impressions                              string,
  follows                                       string,
  conversion_value_in_local_currency            string,
  other_engagements                             string,
  lead_generation_mail_interested_clicks        string,
  opens                                         string,
  total_engagements                             string,
  shares                                        string,
  action_clicks                                 string,
  comments                                      string,
  external_website_post_view_conversions        string,
  landing_page_clicks                           string,
  one_click_lead_form_opens                     string,
  sends                                         string,
  external_website_conversions                  string,
  lead_generation_mail_contact_info_shares      string,
  clicks                                        string,
  reactions                                     string,
  viral_shares                                  string,
  viral_card_impressions                        string,
  viral_one_click_leads                         string,
  viral_external_website_conversions            string,
  viral_comment_likes                           string,
  viral_comments                                string,
  viral_impressions                             string,
  viral_one_click_lead_form_opens               string,
  viral_follows                                 string,
  viral_reactions                               string,
  viral_likes                                   string,
  viral_other_engagements                       string,
  viral_card_clicks                             string,
  viral_external_website_post_view_conversions  string,
  viral_total_engagements                       string,
  viral_company_page_clicks                     string,
  viral_landing_page_clicks                     string,
  viral_external_website_post_click_conversions string,
  viral_clicks                                  string,
  date_range                                    string
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