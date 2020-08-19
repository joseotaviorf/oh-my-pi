--drop view if exists vw_dim_condo;
--create or replace view vw_dim_condo as
select
  c.id as sk_condo,
  c.id as id_condo,
  c.neighborhood,
  c.zipcode,
  c.city,
  c.address,
  c.lat,
  c.lng,
  c.name,
  c.number,
  c.created_in as ts_created,
  c.updated_in as ts_updated,
  now()::timestamp as ts_load
from condo c;