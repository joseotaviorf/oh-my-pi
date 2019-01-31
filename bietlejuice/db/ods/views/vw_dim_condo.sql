drop view if exists vw_dim_condo;
create view vw_dim_condo as
select
  c.id as sk_condo,
  c.id,
  c.updated_in as ts_updated,
  c.created_in as ts_created,
  c.neighborhood,
  c.zipcode,
  c.city,
  c.address,
  c.lat,
  c.lng,
  c.name,
  c.number
from condo c
;