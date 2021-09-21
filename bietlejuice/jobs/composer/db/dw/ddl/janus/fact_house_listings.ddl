drop table if exists janus.fact_house_listings;
create table if not exists janus.fact_house_listings
(
 sk_house_listing BIGINT,
 sk_owner BIGINT,
 sk_region BIGINT,
 sk_user_registration BIGINT,
 sk_contract BIGINT,
 sk_condo BIGINT,
 sk_user_partner_agent BIGINT,
 sk_partner BIGINT,
 sk_autonomous_agent BIGINT,
 sk_stranded_date BIGINT,
 days_listing_to_contract_signed INTEGER,
 days_listing_to_depublication INTEGER,
 days_ended_rental_to_relisting INTEGER,
 days_relisting_to_re_rental INTEGER,
 days_ended_rental_to_re_rented INTEGER,
 nr_renting SMALLINT,
 order_renting SMALLINT,
 ts_load TIMESTAMP
);

ALTER TABLE janus.fact_house_listings OWNER TO airflow;