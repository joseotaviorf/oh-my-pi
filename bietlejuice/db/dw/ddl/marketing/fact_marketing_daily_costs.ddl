DROP TABLE if EXISTS marketing.fact_marketing_daily_costs;
CREATE TABLE if NOT EXISTS marketing.fact_marketing_daily_costs (
    sk_date integer,
    side varchar(16),
    account_name varchar(512),
    campaign_name varchar(512),
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
    ts_load timestamp
)
;