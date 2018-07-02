drop view if exists vw_fact_house_status;
create or replace view vw_fact_house_status as
with distinct_status as (
	select distinct
		id,
		status_history,
		status_time::date as dt_min_status,
		next_status_date as dt_max_status
	from imovel_status_full_history
),
min_max as (
	select distinct
		id,
		status_history,
		dt_min_status,
		case
			when dt_max_status = lead(dt_min_status) over (partition by id order by dt_min_status)
						and status_history = lead(status_history) over (partition by id order by dt_min_status)
				then lead(dt_max_status) over (partition by id order by dt_min_status)
			else dt_max_status
		end as dt_max_status,
		coalesce(not(dt_min_status = lag(dt_max_status) over (partition by id order by dt_min_status)
				and status_history = lag(status_history) over (partition by id order by dt_min_status)), true) as valid
	from distinct_status
)
select
	coalesce(sdp.sk_property, rpad(mm.id::varchar, 12, '0')::bigint) as sk_property,
	coalesce(sdp.regiao_id, -1) as sk_region,
	mm.status_history,
	to_char(mm.dt_min_status, 'YYYYMMDD')::integer as sk_min_status_date,
	to_char(mm.dt_max_status, 'YYYYMMDD')::integer as sk_max_status_date,
	now() as dt_timestamp
from min_max mm
left join staging.dim_property sdp
	on sdp.id = mm.id
		and mm.dt_min_status >= sdp.min_version_time::date
		and coalesce(mm.dt_max_status, now()) <= coalesce(sdp.max_version_time::date, now())
where mm.valid is true
;