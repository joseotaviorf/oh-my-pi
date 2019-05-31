drop table if exists zendesk.dim_ticket;
create table if not exists zendesk.dim_ticket (
    sk_ticket bigint,
    subject varchar(MAX),
    description varchar(MAX),
    channel varchar(10),
    "group" varchar,
    priority varchar(10),
    recipient varchar,
    tags varchar(MAX),
    status varchar(20),
    has_public_comments boolean,
    custom_fields varchar(MAX),
    score varchar(20),
    reason varchar,
    comment varchar(MAX),
    request_type varchar,
    client_type varchar(30),
    ts_created timestamp,
    ts_created_local timestamp,
    ts_updated timestamp,
    ts_load timestamp
);