drop table if exists staging.zendesk_fact_ticket_contact_types;
create table if not exists staging.zendesk_fact_ticket_contact_types (
    sk_ticket bigint,
    contact_type_tag varchar(75),
    client_taxonomy varchar(2),
    category_taxonomy varchar(2)
);
