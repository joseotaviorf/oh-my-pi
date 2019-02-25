drop table if exists fact_house_listings;
create table if not exists fact_house_listings (
  sk_house_listing bigint,
  sk_owner bigint,
  sk_region bigint,
  sk_user_registration bigint,
  sk_contract bigint,
  sk_condo bigint,
  days_first_listing_to_contract_signed integer,
  days_listing_to_depublication integer,
  nr_renting smallint,
  ts_load timestamp
)
;