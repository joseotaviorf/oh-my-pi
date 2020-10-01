drop table if exists staging.zendesk_dim_zendesk_user;
create table if not exists staging.zendesk_dim_zendesk_user (
    sk_zendesk_user bigint,
    is_active boolean,
    url_user varchar (65535),
    name varchar (65535),
    alias varchar (65535),
    email varchar,
    phone varchar,
    is_shared_phone_number boolean,
    time_zone varchar,
    locale varchar,
    tags varchar,
    role varchar,
    ts_last_login timestamp,
    ts_created timestamp,
    ts_created_local timestamp, 
    ts_updated timestamp,
    ts_load timestamp
);