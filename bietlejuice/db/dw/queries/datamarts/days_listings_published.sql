select
  dd.date as date_in_publication,
  hs.sk_house,
  dhl.id_house as house_id
from fact_house_status hs
join dim_house_listing dhl
	on dhl.sk_house_listing = hs.sk_house
join dim_date dd
	on dd.sk_date between hs.sk_min_status_date and coalesce(hs.sk_max_status_date, to_char(current_date, 'YYYYMMDD')::bigint)
where hs.status_history = 'publicado'
order by 1, 2
;