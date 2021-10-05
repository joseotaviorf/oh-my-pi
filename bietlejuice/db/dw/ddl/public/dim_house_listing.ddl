drop table if exists dim_house_listing;
create table if not exists dim_house_listing
(
 sk_house_listing bigint not null  encode lzo
 ,id_house bigint   encode lzo
 ,short_id_house bigint   encode lzo
 ,version smallint   encode lzo
 ,first_key_location varchar(256)   encode lzo
 ,status varchar(256)   encode lzo
 ,is_keys_with_agent_eligible boolean
 ,ts_listing_version_start timestamp without time zone   encode lzo
 ,ts_listing_version_end timestamp without time zone   encode lzo
 ,ts_house_first_publication timestamp without time zone   encode lzo
 ,ts_house_last_publication timestamp without time zone   encode lzo
 ,ts_publication timestamp without time zone   encode lzo
 ,ts_last_de_publication timestamp without time zone   encode lzo
 ,rent numeric(14,2)   encode lzo
 ,house_rent numeric(14,2)   encode lzo
 ,house_neighborhood varchar(256)   encode lzo
 ,house_zipcode varchar(256)   encode lzo
 ,house_city varchar(256)   encode lzo
 ,house_complement varchar(256)   encode lzo
 ,house_condo numeric(14,2)   encode lzo
 ,house_elevator smallint   encode lzo
 ,house_address varchar(256)   encode lzo
 ,house_iptu numeric(14,2)   encode lzo
 ,house_lat numeric(14,7)   encode lzo
 ,house_lng numeric(14,7)   encode lzo
 ,is_house_furnished boolean
 ,house_number varchar(256)   encode lzo
 ,house_bathrooms smallint   encode lzo
 ,house_bedrooms smallint   encode lzo
 ,house_suites smallint   encode lzo
 ,house_garages smallint   encode lzo
 ,house_status varchar(256)   encode lzo
 ,house_type varchar(256)   encode lzo
 ,house_entrance varchar(256)   encode lzo
 ,house_garage_type varchar(256)   encode lzo
 ,is_house_registration_verified boolean
 ,house_total_value numeric(14,2)   encode lzo
 ,house_total_area numeric(14,2)   encode lzo
 ,house_construction_area numeric(14,2)   encode lzo
 ,house_condo_type varchar(256)   encode lzo
 ,house_iptu_type varchar(256)   encode lzo
 ,ts_house_create timestamp without time zone   encode lzo
 ,ts_house_update timestamp without time zone   encode lzo
 ,registration_abandoned_reason varchar(256)   encode lzo
 ,house_unpublished_reason varchar(256)   encode lzo
 ,listing_category_start varchar(256)   encode lzo
 ,is_last_version boolean
 ,is_exclusive boolean
 ,dt_last_exclusive_opted_in date   encode lzo
 ,dt_last_exclusive_opted_out date   encode lzo
 ,who_is_living varchar(256)   encode lzo
 ,key_type varchar(256)   encode lzo
 ,key_location varchar(256)   encode lzo
 ,has_visit_restriction boolean
 ,house_predicted_price numeric(14,2)   encode lzo
 ,is_b2b boolean
 ,b2b_type varchar(256)   encode lzo
 ,b2b_prime_type varchar(256)   encode lzo
 ,is_autonomous_agent boolean
 ,sk_autonomous_agent bigint  encode lzo
 ,is_originals_active boolean
 ,last_originals_type varchar(256)   encode lzo
 ,dt_last_originals_opted_in date   encode lzo
 ,dt_last_originals_opted_out date   encode lzo
 ,is_iorent_active boolean
 ,last_iorent_type varchar(256)   encode lzo
 ,dt_last_iorent_opted_in date   encode lzo
 ,dt_last_iorent_opted_out date   encode lzo
 ,sale_price bigint   encode lzo
 ,is_for_rent boolean
 ,is_for_sale boolean
 ,has_instant_offer_enabled boolean
 ,ts_load timestamp without time zone   encode lzo
 ,primary key (sk_house_listing)
)
diststyle key
distkey (sk_house_listing)
;
