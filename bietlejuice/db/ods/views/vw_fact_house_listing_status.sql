drop view if exists vw_fact_house_listing_status;
create or replace view vw_fact_house_listing_status as
select
  hls.id_house_listing as sk_house_listing,
  coalesce(hls.id_region, -1) as sk_region,
  coalesce(to_char(hls.ts_first_publication, 'YYYYMMDD')::bigint, -1::bigint) as sk_first_publication_date,
  coalesce(to_char(hls.ts_status_start, 'YYYYMMDD')::bigint, -1::bigint) as sk_status_start_date,
  coalesce(to_char(hls.ts_status_end, 'YYYYMMDD')::bigint, -1::bigint) as sk_status_end_date,
  hls.ts_status_start,
  hls.ts_status_end,
  hls.status_history,
  left(hls.status_change_reason, 5000) as status_change_reason,
  now()::timestamp as ts_load
from house_listing_status hls
join house_listing hl
	on hl.id_house_listing = hls.id_house_listing
join house h
    on h.id = hl.id_house and h.is_for_rent::int::boolean
;