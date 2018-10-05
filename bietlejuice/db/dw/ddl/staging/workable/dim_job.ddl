drop table if exists staging.workable_dim_job;
create table if not exists staging.workable_dim_job (
  sk_job varchar not null,
  title varchar,
  full_title varchar,
  shortcode varchar,
  code varchar,
  state varchar,
  department varchar,
  url varchar,
  application_url varchar,
  short_link varchar,
  location_country varchar,
  location_country_code varchar,
  location_region varchar,
  location_city varchar,
  location_zip_code varchar,
  location_telecommuting varchar,
  created_at varchar
)
;