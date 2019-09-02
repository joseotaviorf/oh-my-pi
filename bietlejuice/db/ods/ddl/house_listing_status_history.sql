drop table if exists house_listing_status_history;
create table if not exists house_listing_status_history (
  id_house_listing bigint,
  id_region bigint,
  status_history varchar,
  status_change_reason varchar,
  ts_first_publication timestamp,
  ts_status_start timestamp,
  ts_status_end timestamp,
  ts_load timestamp
);