drop table if exists datalake_raw.crawler_matches;

create external table datalake_raw.crawler_matches (
  id string,
  crawler_id string,
  sk_house_listing string,
  match string,
  created_on string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ','
)
location 's3://5a-datalake/raw/crawler_photos_matcher/crawler_matches/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
