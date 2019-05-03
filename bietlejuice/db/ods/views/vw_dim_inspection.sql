drop view if exists vw_dim_inspection;
create or replace view vw_dim_inspection as
select
  id as sk_inspection,
  id as id_inspection,
  type,
  status,
  ts_created,
  ts_expired,
  is_tenant_approved::boolean,
  is_owner_approved::boolean,
  now()::timestamp as ts_load
from inspection
;