drop table if exists zendesk.fact_ticket_contact_types;
create table if not exists zendesk.fact_ticket_contact_types (
    sk_ticket bigint,
    contact_type_tag varchar(75),
    client_taxonomy varchar(2),
    category_taxonomy varchar(2),
    ts_updated timestamp,
    ts_load timestamp
);
