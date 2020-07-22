drop table if exists quintoandar.fact_listing_price_changes;
create table quintoandar.fact_listing_price_changes (
    sk_smart_price bigint,
    sk_house_listing bigint,
    sk_price_started_date bigint,
    sk_price_ended_date bigint,
    is_smart_pricing_enabled bool,
    price_change_reason varchar,
    rent integer,
    rent_changes integer,
    days_with_same_rent integer,
    ts_price_started timestamp,
    ts_price_ended timestamp,
    ts_load timestamp
);