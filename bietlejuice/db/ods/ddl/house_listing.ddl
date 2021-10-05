drop table if exists house_listing;
create table if not exists house_listing (
  id_house_listing bigint,
  id_house bigint,
  version smallint,
  first_key_location varchar,
  status varchar,
  rent decimal,
  listing_category_start varchar,
  last_originals_type varchar,
  last_iorent_type varchar,
  is_last_version boolean,
  is_exclusive boolean,
  is_keys_with_agent_eligible boolean,
  is_originals_active boolean,
  is_iorent_active boolean,
  ts_listing_version_start timestamp,
  ts_listing_version_end timestamp,
  ts_last_de_publication timestamp,
  dt_last_exclusive_opted_in date,
  dt_last_exclusive_opted_out date,
  dt_last_originals_opted_in date,
  dt_last_originals_opted_out date,
  dt_last_iorent_opted_in date,
  dt_last_iorent_opted_out date
)

create index house_listing_idx_end_v on house_listing (ts_listing_version_end desc);
create index house_listing_idx_start_v on house_listing (ts_listing_version_start desc);
create index house_listing_idx on house_listing (id_house asc);
create index house_listing_idx_listing on house_listing (id_house_listing asc);