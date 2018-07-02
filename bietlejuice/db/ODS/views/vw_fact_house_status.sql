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
	  row_number() over (partition by id order by dt_min_status) as rn,
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
),
rn_max as (
	select id, max(rn) as max_rn
	from min_max
	group by id
),
_fact as (
	select
		mm.id,
		mm.status_history,
		mm.dt_min_status,
		mm.dt_max_status,
		-- because there are some houses with invalid status transitions, the result ends up with one invalid row between
		--   the last status change and the current one
		-- examples: 892765930 and 892777293
		case
			when mm.valid is true
					or (mm.valid is false
								and rm.id is not null
								and mm.status_history = 'publicado'
								and mm.dt_max_status is null
						)
				then true
			else false
		end as valid
	from min_max mm
	left join rn_max rm
		on mm.rn = rm.max_rn
			and mm.id = rm.id
)
select
	coalesce(sdp.sk_property, rpad(f.id::varchar, 12, '0')::bigint) as sk_house,
	f.status_history,
	to_char(f.dt_min_status, 'YYYYMMDD')::integer as sk_min_status_date,
	to_char(f.dt_max_status, 'YYYYMMDD')::integer as sk_max_status_date,
	now() as dt_timestamp
from _fact f
left join staging.dim_property sdp
	on sdp.id = f.id
		and f.dt_min_status >= sdp.min_version_time::date
		and coalesce(f.dt_max_status, now()) <= coalesce(sdp.max_version_time::date, now())
where f.valid is true
;