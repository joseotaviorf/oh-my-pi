drop table if exists zendesk.dim_zendesk_user;

create table if not exists zendesk.dim_zendesk_user (
    sk_zendesk_user int,
    url varchar,
    name varchar,
    email varchar,
    phone varchar,
    time_zone varchar,
    shared_phone_number varchar,
    locale varchar,
    organization_id varchar,
    verified varchar,
    external_id varchar,
    tags varchar,
    role varchar,
    active varchar,
    group_id varchar,
    last_login_at varchar,
    created_at varchar,
    updated_at varchar
)
;