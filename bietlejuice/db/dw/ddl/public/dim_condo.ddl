drop table if exists public.dim_condo;
create table dim_condo(
  sk_condo bigint,
  id bigint,
  dt_updated date,
  dt_created date,
  neighborhood varchar(200),
  zipcode varchar(200),
  city varchar(200),
  address varchar(200),
  lat numeric(10,7),
  lng numeric(10,7),
  name varchar(200),
  number varchar(200),
)
;