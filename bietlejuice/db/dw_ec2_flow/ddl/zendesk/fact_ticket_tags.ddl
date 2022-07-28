drop table if exists zendesk.fact_ticket_tags;
create table if not exists zendesk.fact_ticket_tags (
    sk_ticket bigint,
    ticket_tag varchar(255),
    ts_updated timestamp,
    ts_load timestamp
);
