drop view if exists vw_fact_house_status;
create or replace view vw_fact_house_status as
with distinct_status as (
	select distinct
		id,
		status_history,
		status_time::date as min_status_date,
		next_status_date as max_status_date
	from imovel_status_full_history
),
min_max as (
	select distinct
		id,
		status_history,
		min_status_date,
		case
			when max_status_date = lead(min_status_date) over (partition by id order by min_status_date)
						and status_history = lead(status_history) over (partition by id order by min_status_date)
				then lead(max_status_date) over (partition by id order by min_status_date)
			else max_status_date
		end as max_status_date,
		coalesce(not(min_status_date = lag(max_status_date) over (partition by id order by min_status_date)
				and status_history = lag(status_history) over (partition by id order by min_status_date)), true) as valid
	from distinct_status
)
select
	coalesce(sdp.sk_property, rpad(mm.id::varchar, 12, '0')::bigint) as sk_property,
	mm.id,
	mm.status_history,
	mm.min_status_date,
	mm.max_status_date
from min_max mm
left join staging.dim_property sdp
	on sdp.id = mm.id
		and mm.min_status_date >= sdp.min_version_time::date
		and coalesce(mm.max_status_date, now()) <= coalesce(sdp.max_version_time::date, now())
where mm.valid is true
;