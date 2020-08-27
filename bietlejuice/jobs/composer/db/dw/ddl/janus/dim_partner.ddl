drop table if exists janus.dim_partner;
create table janus.dim_partner (
    sk_partner bigint primary key,
    id_partner bigint,
    name varchar(255),
    trade_name varchar(255),
    phone varchar(255),
    email varchar(255),
    cnpj varchar(255),
    creci varchar(255),
    type varchar(255),
    ts_partnership_started timestamp,
    ts_created timestamp,
    ts_updated timestamp,
    ts_load timestamp
);