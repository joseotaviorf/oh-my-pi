drop table if exists partner;
create table if not exists partner (
    id bigint,
    id_amplitude_device varchar,
    name varchar,
    phone varchar,
    email varchar,
    cnpj varchar,
    creci varchar,
    type varchar,
    ts_joined_partnership timestamp,
    ts_updated timestamp,
    ts_created timestamp,
    trade_name varchar
);
