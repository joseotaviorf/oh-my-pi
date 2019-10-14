DROP TABLE if EXISTS marketing.fact_affiliate_daily_cost_attributions;
CREATE TABLE if NOT EXISTS marketing.fact_affiliate_daily_cost_attributions (
    sk_date INTEGER,
    city_group VARCHAR(64),
    mkt_origin VARCHAR(128),
    commission_listing numeric(10,2),
    commission_rent numeric(10,2),
    commission_mgm numeric(10,2),
    promotional_bonus numeric(10,2),
    notification numeric(10,2),
    other numeric(10,2),
    commission_tradecom numeric(10,2),
    ts_load TIMESTAMP
)
;