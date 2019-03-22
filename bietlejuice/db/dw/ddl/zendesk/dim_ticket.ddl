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
    status varchar,
    has_public_comments boolean,
    custom_fields varchar(3000),
    score varchar,
    reason varchar,
    comment varchar(2000),
    request_type varchar,
    client_type varchar,
    ts_chat_started timestamp,
    ts_created timestamp,
    ts_updated timestamp,
    ts_load timestamp
)