drop table if exists quintoandar.fact_smart_price_status_changes;
create table quintoandar.fact_smart_price_status_changes (
    sk_smart_price bigint,
    sk_house_listing bigint,
    sk_status_started_date bigint,
    sk_status_ended_date bigint,
    status varchar,
    status_change_reason varchar,
    is_enabled boolean,
    operation_mode varchar,
    days_in_status integer,
    ts_status_started timestamp,
    ts_status_ended timestamp,
    ts_load timestamp
);