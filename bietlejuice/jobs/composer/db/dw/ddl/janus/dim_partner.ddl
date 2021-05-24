drop table if exists janus.dim_partner;
create table janus.dim_partner (
    sk_partner bigint primary key,
    id_partner bigint,
    id_amplitude_device varchar(255),
    name varchar(255),
    trade_name varchar(255),
    phone varchar(255),
    email varchar(255),
    cnpj varchar(255),
    creci varchar(255),
    type varchar(255),
    city varchar(255),
    utm_campaign varchar(255),
    utm_medium varchar(255),
    utm_source varchar(255),
    ts_partnership_started timestamp,
    ts_created timestamp,
    ts_updated timestamp,
    ts_load timestamp
);