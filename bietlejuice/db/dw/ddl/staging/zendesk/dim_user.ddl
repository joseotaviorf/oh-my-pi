drop table if exists staging.zendesk_dim_user;
create table if not exists staging.zendesk_dim_user (
    sk_zendesk_user bigint,
    is_active boolean,
    url_user varchar,
    name varchar,
    alias varchar,
    email varchar,
    phone varchar,
    is_shared_phone_number boolean,
    time_zone varchar,
    locale varchar,
    id_organization int,
    is_verified boolean,
    id_external int,
    tags varchar,
    role varchar,
    id_group int,
    ts_last_login timestamp,
    ts_created timestamp,
    ts_created_local timestamp, 
    ts_updated timestamp,
    ts_load timestamp
);