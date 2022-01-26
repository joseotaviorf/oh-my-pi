DROP TABLE if EXISTS marketing.fact_monthly_demand_funnel_conversions;
CREATE TABLE if NOT EXISTS marketing.fact_monthly_demand_funnel_conversions (
    sk_date integer,
    city_group varchar,
    mkt_category varchar,
    mkt_flow varchar,
    mkt_completion varchar,
    mkt_origin varchar,
    mkt_channel varchar,
    mkt_medium varchar,
    mkt_source varchar,
    mkt_platform varchar,
    utm_campaign varchar(2048),
    utm_term varchar(512),
    utm_content varchar(512),
    cost numeric(16,4),
    total_monthly_sessions integer,
	total_monthly_active_users integer,
	total_monthly_visits_booked integer,
	total_monthly_visits_confirmed integer,
	total_monthly_offers_submitted integer,
	total_monthly_offers_approved integer,
	total_monthly_contracts_signed integer,
    ts_load timestamp
)
;