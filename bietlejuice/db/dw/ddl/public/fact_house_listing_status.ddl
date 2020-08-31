drop table if exists fact_house_listing_status;
create table if not exists fact_house_listing_status (
  sk_house_listing bigint,
  sk_region bigint,
  sk_first_publication_date bigint,
  sk_status_start_date bigint,
  sk_status_end_date bigint,
  ts_status_start timestamp,
  ts_status_end timestamp,
  status_history varchar,
  status_change_reason varchar(5000),
  is_last_status_of_day boolean,
  ts_load timestamp
);
