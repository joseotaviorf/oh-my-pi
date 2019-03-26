drop table if exists partner_agent;
create table if not exists partner_agent (
    id bigint,
    status varchar(255),
    partner_id bigint,
    user_id bigint,
    ts_updated timestamp,
    ts_created timestamp
);