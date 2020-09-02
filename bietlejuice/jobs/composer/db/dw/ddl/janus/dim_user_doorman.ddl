drop table if exists janus.dim_user_doorman;
create table janus.dim_user_doorman(
    sk_user_doorman bigint primary key,
    sk_user_affiliate bigint,
    id_user_doorman bigint,
    id_doorman_occupation bigint,
    id_work_place varchar(255),
    work_address varchar(1024),
    work_street varchar(255),
    work_house_number integer,
    work_neighborhood varchar(255),
    work_city varchar(255),
    work_state varchar(255),
    work_lat decimal(10,0),
    work_lng decimal(10,0),
    recruiter varchar(255),
    subscription_source varchar(255),
    occupation_name varchar(255),
    is_active boolean,
    ts_created timestamp,
    ts_updated timestamp,
    ts_joined timestamp,
    ts_load timestamp
);