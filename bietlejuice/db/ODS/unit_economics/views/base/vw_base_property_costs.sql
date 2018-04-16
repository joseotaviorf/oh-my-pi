drop view if exists unit_economics.vw_base_property_costs;
create or replace view unit_economics.vw_base_property_costs as
select
  ((id || '00') || coalesce(version, 1))::bigint as sk_property,
  id as property_id,
  version,
  min_version_time as publication_date,
  status,
  min_version_time,
  coalesce(max_version_time, '2300-01-01')::date as max_version_time
from public.property_listing
;