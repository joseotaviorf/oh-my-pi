-- we select all columns explicitly below,
-- because schema changes will break our CARTO DAG
SELECT
	sk_house_listing,
	sk_owner,
	sk_region,
	sk_user_registration,
	sk_contract,
	sk_condo,
	sk_user_partner_agent,
	sk_partner,
	sk_stranded_date,
	days_listing_to_contract_signed,
	days_listing_to_depublication,
	days_ended_rental_to_relisting,
	days_relisting_to_re_rental,
	days_ended_rental_to_re_rented,
	nr_renting,
	ts_load,
	CURRENT_TIMESTAMP AS carto_ts_load
FROM public.fact_house_listings;
