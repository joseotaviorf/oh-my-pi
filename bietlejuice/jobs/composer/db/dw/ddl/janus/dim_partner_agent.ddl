drop table if exists janus.dim_partner_agent;
create table janus.dim_partner_agent (
    sk_partner_agent bigint primary key,
    id_partner_agent bigint,
    id_user bigint,
    id_partner bigint,
    status varchar,
    ts_created timestamp,
    ts_updated timestamp,
    ts_load timestamp
);