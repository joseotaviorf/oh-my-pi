drop table if exists dim_user_doorman;

create table public.dim_user_doorman(
    sk_user_doorman bigint primary key,
    id_user_doorman bigint,
    work_address varchar(1024),
    work_street varchar(255),
    work_house_number varchar(255),
    work_neighbourhood varchar(255),
    work_city varchar(255),
    work_state varchar(255),
    work_lat decimal,
    work_lng decimal,
    work_place_id varchar(255),
    recruiter varchar(255),
    subscription_source varchar(255),
    occupation_id bigint,
    occupation_name varchar(255),
    ts_updated timestamp,
    ts_created timestamp,
    ts_joined_program timestamp,
    sk_user_affiliate bigint,
    is_active boolean,
    ts_load timestamp without time zone
);
