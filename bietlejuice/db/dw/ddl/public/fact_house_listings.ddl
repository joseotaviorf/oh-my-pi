drop table if exists fact_house_listings;
create table if not exists fact_house_listings
(
 sk_house_listing bigint   encode lzo
 ,sk_owner bigint   encode lzo
 ,sk_region bigint   encode lzo
 ,sk_user_registration bigint   encode lzo
 ,sk_contract bigint   encode lzo
 ,sk_condo bigint   encode lzo
 ,sk_user_partner_agent bigint   encode lzo
 ,sk_partner bigint   encode lzo
 ,sk_autonomous_agent bigint   encode lzo
 ,sk_stranded_date bigint   encode lzo
 ,days_listing_to_contract_signed integer   encode lzo
 ,days_listing_to_depublication integer   encode lzo
 ,days_ended_rental_to_relisting integer   encode lzo
 ,days_relisting_to_re_rental integer   encode lzo
 ,days_ended_rental_to_re_rented integer   encode lzo
 ,nr_renting smallint   encode lzo
 ,order_renting smallint   encode lzo
 ,ts_load timestamp without time zone   encode lzo
)
diststyle key
distkey (sk_house_listing)
;

ALTER TABLE public.fact_house_listings OWNER TO airflow;