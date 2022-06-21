drop table if exists public.dim_partner;
create table public.dim_partner (
    sk_partner bigint primary key,
    id_partner bigint,
    id_amplitude_device varchar(255),
    country_code VARCHAR,
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
    ts_joined_partnership timestamp,
    ts_created timestamp,
    ts_updated timestamp,
    ts_load timestamp
);

ALTER TABLE public.dim_partner OWNER TO databricks;