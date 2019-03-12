drop table if exists dim_partner;
create table dim_partner (
    sk_partner bigint,
    id_partner bigint,
    name varchar,
    phone varchar,
    email varchar,
    cnpj varchar,
    creci varchar,
    ts_joined_partnership timestamp,
    ts_updated timestamp,
    ts_created timestamp,
    ts_load timestamp
);