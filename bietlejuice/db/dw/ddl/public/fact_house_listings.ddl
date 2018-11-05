drop table if exists fact_house_listings;
create table if not exists fact_house_listings (
  sk_house_listing bigint,
  sk_user_registration bigint,
  sk_contract bigint,
  seconds_first_listing_to_contract_signed integer,
  seconds_listing_to_depublication integer,
  nr_renting smallint,
  ts_load timestamp
)
;