drop table if exists datalake_clean.workable_jobs;
create external table datalake_clean.workable_jobs (
  code string,
  title string,
  url string,
  created_at string,
  short_link string,
  full_title string,
  state string,
  application_url string,
  location_city string,
  location_region_code string,
  location_telecommuting string,
  location_country string,
  location_region string,
  location_country_code string,
  location_zip_code string,
  department string,
  short_code string,
  id string
)
stored as parquet
location 's3://5a-datalake/clean/workable/jobs/'
;

