drop table if exists zendesk.dim_ticket;

create table if not exists zendesk.dim_ticket (
    sk_ticket int,
    subject varchar(65535),
    description varchar(65535),
    channel varchar,
    box varchar,
    priority varchar,
    recipient varchar(65535),
    tags varchar(65535),
    satisfaction_rating varchar(65535),
    request_type varchar,
    client_type varchar,
    chat_started_at varchar,
    created_at varchar,
    ts_load varchar
)