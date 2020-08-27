drop table if exists dim_partner;
create table dim_partner (
    sk_partner bigint primary key,
    id_partner bigint,
    name varchar(255)  DEFAULT NULL,
    trade_name varchar(255)  DEFAULT NULL,
    phone varchar(255) DEFAULT NULL,
    email varchar(255) DEFAULT NULL,
    cnpj varchar(255)  DEFAULT NULL,
    creci varchar(255) DEFAULT NULL,
    type varchar(255) DEFAULT NULL,
    ts_joined_partnership timestamp,
    ts_updated timestamp,
    ts_created timestamp,
    ts_load timestamp
);
