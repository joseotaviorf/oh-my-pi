select
  dd.date as date_in_publication,
  hs.sk_house_listing,
  dhl.id_house as house_id,
  dhl.house_city,
  current_timestamp as ts_load
from fact_house_listing_status hs
join dim_house_listing dhl
	on dhl.sk_house_listing = hs.sk_house_listing
join dim_date dd
	on dd.sk_date between hs.sk_status_start_date and coalesce(hs.sk_status_end_date, to_char(current_date, 'YYYYMMDD')::bigint)
where hs.status_history = 'publicado'
order by 1, 2
;
