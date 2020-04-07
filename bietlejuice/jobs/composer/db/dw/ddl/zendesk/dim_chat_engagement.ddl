drop table if exists zendesk.dim_chat_engagement;
create table if not exists zendesk.dim_chat_engagement (
    sk_chat_engagement varchar(30),
    started_by varchar(20),
    ts_started timestamp,
    ts_started_local timestamp,
    ts_ended timestamp,
    ts_ended_local timestamp,
    ts_load timestamp
)