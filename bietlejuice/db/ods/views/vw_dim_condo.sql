drop view if exists vw_dim_condo;
create view vw_dim_condo as
select
  c.id as sk_condo,
  c.id as id_condo,
  c.updated_in as dt_updated,
  c.created_in as dt_created,
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