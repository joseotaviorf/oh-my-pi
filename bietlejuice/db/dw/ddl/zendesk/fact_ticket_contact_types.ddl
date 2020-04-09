drop table if exists zendesk.fact_ticket_contact_types;
create table if not exists zendesk.fact_ticket_contact_types (
    sk_ticket bigint,
    sk_updated bigint,
    contact_type_tag varchar(75),
    client_taxonomy varchar(5),
    category_taxonomy varchar(5),
    ts_updated timestamp,
    ts_load timestamp
);
