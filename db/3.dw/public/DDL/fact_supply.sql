drop table public.fact_suppy;

create table public.fact_supply (
	ods_id bigint NOT NULL,
	sk_lead integer,
	sk_conversion integer,
	sk_photo_job integer,
	sk_property bigint,
	sk_user_rep integer,
	sk_user_affiliate integer,
	sk_user_owner integer,
	sk_user_photographer integer,
	sk_region integer,
	sk_lead_date integer,
	sk_prospect_date integer,
	sk_qualified_date integer,
	sk_opportunity_date integer,
	sk_first_listing_date integer,
	flow varchar(255),
	acquisition_method varchar(255),
	acquisition_channel varchar(255),
	lead_to_prospect_diff_minutes integer,
	prospect_to_qualified_diff_minutes integer,
	qualified_to_opportunity_diff_minutes integer,
	opportunity_to_listing_diff_minutes integer,
	lead_to_listing_diff_minutes integer
)