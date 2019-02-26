with t_dates as (
	select
		cast(id_origin as bigint) as lead_id,
		cast(score_factor as bigint) as score_factor,
		row_number() over (partition by id_origin order by dt, ts_start) as rn
	from
		datalake_clean.crm_tasks
	where origin = 'Lead'
)
select
	lead_id,
	score_factor
from
	t_dates
	where rn = 1