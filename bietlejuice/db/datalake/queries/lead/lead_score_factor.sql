with t_dates as (
	select
		id_origin,
		min(dt) as dt
	from
		datalake_clean.crm_tasks
	where origin = 'Lead'
	group by 1
)
select
	cast(t.id_origin as bigint) as lead_id,
	cast(t.score_factor as bigint) as score_factor
from
	t_dates td
join
	datalake_clean.crm_tasks t
	on td.id_origin = t.id_origin and td.dt = t.dt and t.origin = 'Lead'