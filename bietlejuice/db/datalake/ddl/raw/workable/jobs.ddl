drop table if exists datalake_raw.workable_jobs;
create external table if not exists datalake_raw.workable_jobs (
  code string,
  title string,
  url string,
  created_at string,
  shortlink string,
  full_title string,
  state string,
  application_url string,
  location struct<
    city:string,
    region_code:string,
    telecommuting:string,
    country:string,
    region:string,
    country_code:string,
    zip_code:string
  >,
  department string,
  shortcode string,
  id string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/workable/jobs/'
;


