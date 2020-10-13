--drop view if exists vw_dim_inspection;
--create or replace view vw_dim_inspection as
select
  id as sk_inspection,
  id as id_inspection,
  type,
  mode,
  status,
  ts_created,
  ts_expired,
  is_tenant_approved::boolean,
  is_owner_approved::boolean,
  coalesce(has_inspector_comment::boolean, false) as has_inspector_comment,
  coalesce(has_tenant_comment::boolean, false) as has_tenant_comment,
  coalesce(has_owner_comment::boolean, false) as has_owner_comment,
  now()::timestamp as ts_load
from inspection
;