drop table if exists staging.dim_partner;
create table staging.dim_partner (
    sk_partner bigint,
    id_partner bigint,
    id_amplitude_device varchar,
    name varchar,
    trade_name varchar,
    phone varchar,
    email varchar,
    cnpj varchar,
    creci varchar,
    type varchar,
    utm_campaign varchar,
    utm_medium varchar,
    utm_source varchar,
    ts_joined_partnership timestamp,
    ts_updated timestamp,
    ts_created timestamp,
    ts_load timestamp
);