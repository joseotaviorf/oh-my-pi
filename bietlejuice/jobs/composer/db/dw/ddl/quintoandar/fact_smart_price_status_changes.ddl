drop table if exists quintoandar.fact_smart_price_status_changes;
create table quintoandar.fact_smart_price_status_changes (
    sk_smart_price bigint,
    sk_house_listing bigint,
    sk_status_started_date bigint,
    sk_status_ended_date bigint,
    status varchar,
    status_change_reason varchar,
    operation_mode varchar,
    is_enabled boolean,
    days_in_status integer,
    ts_status_started timestamp,
    ts_status_ended timestamp,
    ts_load timestamp
);

ALTER TABLE quintoandar.fact_smart_price_status_changes owner to airflow;
