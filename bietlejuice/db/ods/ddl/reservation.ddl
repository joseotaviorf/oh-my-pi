drop table if exists reservation;
create table if not exists reservation (
    id bigint primary key,
    created_at timestamp not null,
    updated_at timestamp not null,
    version integer not null,
    attempt integer not null,
    rent_flow_id bigint,
    status varchar(255),
    tenant_id bigint,
    value decimal(19,2),
    house_id bigint,
    mundipagg_token varchar(255),
    is_ongoing integer,
    cancellation_reason varchar(255),
    installments integer
);
