drop table if exists fact_house_listing_status_history;
create table if not exists fact_house_listing_status_history (
  sk_house_listing bigint,
  sk_region bigint,
  sk_first_publication_date bigint,
  sk_status_start_date bigint,
  sk_status_end_date bigint,
  status_history varchar,
  status_change_reason varchar(5000),
  ts_load timestamp
);