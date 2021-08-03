drop table if exists janus.dim_condo;
create table janus.dim_condo (
    sk_condo bigint primary key,
    id_condo bigint,
    neighborhood varchar,
    zipcode varchar,
    city varchar,
    address varchar,
    lat numeric(10,7),
    lng numeric(10,7),
    name varchar,
    number varchar,
    ts_created timestamp,
    ts_updated timestamp,
    ts_load timestamp
);

ALTER TABLE janus.dim_condo OWNER TO airflow;
