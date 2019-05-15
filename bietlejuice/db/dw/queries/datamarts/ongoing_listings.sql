select
    week_start,
    weeks_since_publication,
    status_history,
	sk_house
from(
select
    fhs.*,
    rank() over(partition by dd.week_start, fhs.sk_house order by coalesce(fhs.sk_min_status_date, to_char(current_date -1, 'YYYYMMDD')::bigint) desc) as rk,
    dd.date,
    date(dh.ts_publication) as ts_publication,
    date_diff('week', dh.ts_publication, dd.week_start) as weeks_since_publication,
    dd.weekday_name,
    dd.week_start,
    dh.is_last_version
from fact_house_status fhs
join dim_date dd
  on dd.sk_date between fhs.sk_min_status_date and coalesce(fhs.sk_max_status_date, to_char(current_date -1, 'YYYYMMDD')::bigint)
left join dim_house_listing dh
  on fhs.sk_house = dh.sk_house_listing
where dd.weekday_name = 'Sunday'
)
where
	rk = 1
	and status_history in ('suspenso','publicado')