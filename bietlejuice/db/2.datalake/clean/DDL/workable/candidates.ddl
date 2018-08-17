drop table if exists datalake_clean.workable_candidates;
create external table datalake_clean.workable_candidates (
  id string,
  name string,
  first_name string,
  last_name string,
  headline string,
  account_subdomain string,
  account_name string,
  job_short_code string,
  job_title string,
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
stored as parquet
location 's3://5a-datalake/clean/workable/candidates/'
;

