DROP TABLE if EXISTS marketing.fact_weekly_supply_funnel_conversions;
CREATE TABLE if NOT EXISTS marketing.fact_weekly_supply_funnel_conversions (
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
    total_weekly_sessions integer,
    total_weekly_active_users integer,
    total_weekly_leads integer,
    total_weekly_prospects integer,
    total_weekly_qualifieds integer,
    total_weekly_opportunities integer,
    total_weekly_listings integer,
    ts_load timestamp
)
;