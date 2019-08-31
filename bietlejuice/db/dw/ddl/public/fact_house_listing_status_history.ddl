drop table if exists fact_house_listing_status_history;
create table if not exists fact_house_listing_status_history (
  sk_house_listing bigint,
  sk_region bigint,
  status_history varchar,
  ts_first_publication timestamp,
  ts_status_start timestamp,
  ts_status_end timestamp,
  status_change_reason varchar,
  ts_load timestamp
);