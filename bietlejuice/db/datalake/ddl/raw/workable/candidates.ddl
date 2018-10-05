drop table if exists datalake_raw.workable_candidates;
create external table if not exists datalake_raw.workable_candidates (
  id string,
  name string,
  firstname string,
  lastname string,
  headline string,
  account struct<
    subdomain:string,
    name:string
  >,
  job struct<
    shortcode:string,
    title:string
  >,
  stage string,
  disqualified string,
  disqualification_reason string,
  sourced string,
  profile_url string,
  email string,
  domain string,
  created_at string,
  updated_at string,
  hired_at string,
  address string,
  phone string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/workable/candidates/'
;


