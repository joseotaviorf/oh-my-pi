drop table if exists public.condo;
create table if not exists condo (
  id bigint primary key,
  updated_in date,
  created_in date,
  neighborhood varchar(200),
  zipcode varchar(200),
  city varchar(200),
  address varchar(200),
  lat numeric(10,7),
  lng numeric(10,7),
  name varchar(255),
  number varchar(200),
  condo_manager_id bigint,
  rules text
);