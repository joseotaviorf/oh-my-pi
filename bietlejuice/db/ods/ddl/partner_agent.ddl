drop table if exists partner_agent;
create table if not exists partner_agent (
    id bigint,
    status varchar(255),
    partner_id bigint,
    user_id bigint,
    type varchar,
    ts_updated timestamp,
    ts_created timestamp
);

CREATE INDEX user_id_idx ON public."partner_agent" (user_id);
