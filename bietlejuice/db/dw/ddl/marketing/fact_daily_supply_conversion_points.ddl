DROP TABLE if EXISTS marketing.fact_daily_supply_conversion_points;
CREATE TABLE if NOT EXISTS marketing.fact_daily_supply_conversion_points (
    sk_date integer,
    city_group varchar(256),
    mkt_category varchar(256),
    mkt_flow varchar(256),
    mkt_completion varchar(256),
    mkt_channel varchar(256),
    mkt_medium varchar(256),
    mkt_source varchar(256),
    mkt_platform varchar(256),
    utm_campaign varchar(512),
    utm_term varchar(512),
    utm_content varchar(512),
    cost numeric(16,4),
    total_daily_sessions bigint,
    total_daily_active_users bigint,
    total_daily_leads bigint,
    total_daily_listings bigint,
    ts_load timestamp
)
;