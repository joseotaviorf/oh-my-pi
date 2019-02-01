drop table if exists dim_user_affiliate;

create table public.dim_user_affiliate (
    sk_affiliate bigint primary key,
    id_affiliate bigint,
    ts_joined_program timestamp,
    category varchar(62),
    work_city varchar(255),
    is_active boolean,
    ts_updated timestamp,
    ts_created timestamp,
    creci_number varchar(62),
    origin varchar(24),
    type varchar(62),
    ts_load timestamp without time zone
);