select
    week_start,
    weeks_since_publication,
    status_history,
   	sk_house_listing
from(
select
    fhs.*,
    rank() over(partition by dd.week_start, fhs.sk_house_listing order by coalesce(fhs.sk_status_start_date, to_char(current_date -1, 'YYYYMMDD')::bigint) desc) as rk,
    dd.date,
    date(dh.ts_publication) as ts_publication,
    date_diff('week', dh.ts_publication, dd.week_start) as weeks_since_publication,
    dd.weekday_name,
    dd.week_start,
    dh.is_last_version
from fact_house_listing_status fhs
join dim_date dd
  on dd.sk_date between fhs.sk_status_start_date and coalesce(to_char(to_date(nullif(fhs.sk_status_end_date,-1), 'YYYYMMDD') - 1, 'YYYYMMDD')::bigint, to_char(current_date -1, 'YYYYMMDD')::bigint)
left join dim_house_listing dh
  on fhs.sk_house_listing = dh.sk_house_listing
where dd.weekday_name = 'Sunday'
)
where
	rk = 1
	and status_history in ('suspenso','publicado')
;