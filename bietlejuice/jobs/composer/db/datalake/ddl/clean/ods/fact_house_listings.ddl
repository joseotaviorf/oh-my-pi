CREATE TABLE IF NOT EXISTS dw_public.fact_house_listings (
 sk_house_listing string,
 sk_owner string,
 sk_region string,
 sk_user_registration string,
 sk_contract string,
 sk_condo string,
 sk_user_partner_agent string,
 sk_partner string,
 sk_stranded_date string,
 days_listing_to_contract_signed string,
 days_listing_to_depublication string,
 days_ended_rental_to_relisting string,
 days_relisting_to_re_rental string,
 days_ended_rental_to_re_rented string,
 nr_renting string,
 ts_load string
)
USING CSV
OPTIONS (
  path 's3://5a-datalake/clean/ods/house_listings',
  header 'true',
  inferSchema 'true'
)