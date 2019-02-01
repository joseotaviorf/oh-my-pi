drop table if exists dim_user_affiliate;

create table public.dim_user_affiliate (
    sk_user_affiliate bigint primary key,
    id_user_affiliate bigint,
    ts_joined_program timestamp,
    category varchar(62),
    work_city varchar(255),
    is_active boolean,
    ts_updated timestamp,
    ts_created timestamp,
    creci_number varchar(62),
    origin varchar(24),
    type varchar(62),
    tracking_source varchar(255),
    tracking_medium varchar(255),
    tracking_platform varchar(255),
    tracking_device_type varchar(255),
    tracking_country varchar(255),
    tracking_state varchar(255),
    tracking_city varchar(255),
    ts_load timestamp without time zone
);