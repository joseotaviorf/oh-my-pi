with t_dates as (
	select
		id_origin,
		id as task_id,
		dt,
		row_number() over (partition by id_origin order by dt, ts_start) as rn
	from
		datalake_clean.crm_tasks
	where origin = 'Lead'
)
select
	cast(td.id_origin as bigint) as lead_id,
	cast(t.score_factor as bigint) as score_factor
from
	t_dates td
join
	datalake_clean.crm_tasks t
	on td.task_id = t.id and t.origin = 'Lead' and t.dt = td.dt
where score_factor is not null and rn=1