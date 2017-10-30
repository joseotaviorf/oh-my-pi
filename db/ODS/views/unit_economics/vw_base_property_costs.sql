drop view if exists vw_base_property_costs;
create or replace view vw_base_property_costs as
select
  ((id || '00') || coalesce(version, 1))::bigint as sk_property,
  id as property_id,
  version,
  publication_date,
  last_status_version,
  coalesce(min_version_time, '1900-01-01')::date as min_version_time,
  coalesce(max_version_time, '2300-01-01')::date as max_version_time
from vw_property_listing
;
