drop table if exists janus.dim_user_doorman;
create table janus.dim_user_doorman(
    sk_user_doorman bigint primary key,
    sk_user_affiliate bigint,
    id_user_doorman bigint,
    occupation_id bigint,
    work_place_id varchar(255),
    work_address varchar(1024),
    work_street varchar(255),
    work_house_number varchar(255),
    work_neighbourhood varchar(255),
    work_city varchar(255),
    work_state varchar(255),
    work_lat decimal,
    work_lng decimal,
    recruiter varchar(255),
    subscription_source varchar(255),
    occupation_name varchar(255),
    is_active boolean,
    ts_created timestamp,
    ts_updated timestamp,
    ts_joined_program timestamp,
    ts_load timestamp
);

ALTER TABLE janus.dim_user_doorman OWNER TO airflow;