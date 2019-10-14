DROP TABLE if EXISTS marketing.fact_affiliate_daily_cost_attributions;
CREATE TABLE if NOT EXISTS marketing.fact_affiliate_daily_cost_attributions (
    sk_date BIGINT,
    city_group VARCHAR(64),
    mkt_origin VARCHAR(128),
    commission_listing NUMERIC(14,2),
    commission_rent NUMERIC(14,2),
    commission_mgm NUMERIC(14,2),
    promotional_bonus NUMERIC(14,2),
    notification NUMERIC(14,2),
    other NUMERIC(14,2),
    commission_tradecom NUMERIC(14,2),
    ts_load TIMESTAMP
)
;