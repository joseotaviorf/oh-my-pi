drop view if exists vw_fact_house_listing_status_history;
create or replace view vw_fact_house_listing_status_history as
select
  id_house_listing as sk_house_listing,
  coalesce(id_region, -1) as sk_region,
  coalesce(to_char(ts_first_publication, 'YYYYMMDD')::bigint, -1::bigint) as sk_first_publication_date,
  coalesce(to_char(ts_status_start, 'YYYYMMDD')::bigint, -1::bigint) as sk_status_start_date,
  coalesce(to_char(ts_status_end, 'YYYYMMDD')::bigint, -1::bigint) as sk_status_end_date,
  status_history,
  left(status_change_reason, 5000) as status_change_reason,
  now()::timestamp as ts_load
from house_listing_status_history
;