drop table if exists staging.zendesk_fact_ticket_tags;
create table if not exists staging.zendesk_fact_ticket_tags (
    sk_ticket bigint,
    ticket_tag varchar(255),
    ts_updated timestamp,
    ts_load timestamp
);
