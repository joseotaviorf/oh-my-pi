drop table if exists fact_house_listings;
create table if not exists fact_house_listings (
  sk_house_listing bigint,
  sk_owner bigint,
  sk_region bigint,
  sk_user_registration bigint,
  sk_contract bigint,
  sk_condo bigint,
  sk_user_partner_agent bigint,
  sk_partner bigint,
  sk_stranded_date bigint,
  days_listing_to_contract_signed integer,
  days_listing_to_depublication integer,
  days_ended_rental_to_relisting integer,
  days_relisting_to_re_rental integer,
  days_ended_rental_to_re_rented integer,
  nr_renting smallint,
  ts_load timestamp
)
;

