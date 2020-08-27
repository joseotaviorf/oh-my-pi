DROP TABLE IF EXISTS datalake_raw.gsheets_taxonomy_affiliates;
CREATE TABLE datalake_raw.gsheets_taxonomy_affiliates (
  affiliate_type string,
  tracking_source string,
  tracking_medium string,
  tracking_campaign string,
  mkt_origin string,
  mkt_channel string,
  mkt_medium string,
  mkt_source string
)
USING JSON
OPTIONS (path 's3://{OLD_DATALAKE_BUCKET}/raw/gsheets/taxonomy_affiliates')