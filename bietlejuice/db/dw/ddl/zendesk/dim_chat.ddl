drop table if exists zendesk.dim_chat;
create table if not exists zendesk.dim_chat (
    sk_chat varchar(30),
    tags varchar(5000),
    started_by varchar(20),
    visitor_phone varchar(500),
    status varchar(30),
    is_retained_by_bot boolean,
    is_missed boolean,
    is_proactive boolean,
    ts_started timestamp,
    ts_started_local timestamp,
    ts_ended timestamp,
    ts_ended_local timestamp,
    ts_updated timestamp,
    ts_load timestamp
)