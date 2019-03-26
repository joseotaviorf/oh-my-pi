drop table if exists dim_condo;
create table dim_condo (
  sk_condo bigint,
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
