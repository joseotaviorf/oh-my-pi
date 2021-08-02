drop table if exists janus.dim_user_affiliate;
create table janus.dim_user_affiliate (
    sk_user_affiliate bigint primary key,
    sk_user bigint,
    id_user_affiliate bigint,
    sk_user_indicated_by bigint,
    origin varchar(255),
    type varchar(255),
    marketing_city_group varchar(255),
    regional varchar(255),
    tracking_source varchar(255),
    tracking_medium varchar(255),
    tracking_campaign varchar(255),
    tracking_content varchar(255),
    tracking_term varchar(255),
    tracking_platform varchar(255),
    tracking_device_type varchar(255),
    tracking_country varchar(255),
    tracking_state varchar(255),
    tracking_city varchar(255),
    mkt_origin varchar(255),
    mkt_channel varchar(255),
    mkt_medium varchar(255),
    mkt_source varchar(255),
    is_realstate_agent boolean,
    is_photographer boolean,
    is_active boolean,
    ts_joined_program timestamp,
    ts_created timestamp,
    ts_updated timestamp,
    ts_load timestamp
);

ALTER TABLE janus.dim_user_affiliate OWNER TO airflow;