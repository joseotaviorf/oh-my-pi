drop table if exists dim_partner_agent;
create table dim_partner_agent (
    sk_partner_agent bigint,
    id_partner_agent bigint,
    status_partner_agent varchar, 
    id_user bigint,
    id_partner bigint,
    type varchar,
    ts_updated timestamp,
    ts_created timestamp,
    ts_load timestamp
);