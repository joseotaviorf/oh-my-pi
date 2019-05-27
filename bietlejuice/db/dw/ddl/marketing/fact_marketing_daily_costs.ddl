DROP TABLE if EXISTS marketing.fact_marketing_daily_costs;
CREATE TABLE if NOT EXISTS marketing.fact_marketing_daily_costs (
    sk_date integer,
    funnel_side varchar(16),
    account_name varchar(512),
    campaign_name varchar(512),
    city_group varchar,
    mkt_category varchar,
    mkt_flow varchar,
    mkt_completion varchar,
    mkt_channel varchar,
    mkt_medium varchar,
    mkt_source varchar,
    mkt_platform varchar,
    utm_campaign varchar(512),
    utm_term varchar(512),
    utm_content varchar(512),
    cost numeric(16,4),
    ts_load timestamp
)
;