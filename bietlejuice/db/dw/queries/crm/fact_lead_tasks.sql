 with task_metrics as (
 SELECT
    sk_task,
    sk_lead,
	min(case when action_type = 'CREATE' then sk_action_date else null end) over (partition by sk_task order by ts_action ROWS UNBOUNDED PRECEDING)
 		as sk_created_date,
 	min(case when action_type = 'REALIZE' then sk_action_date else null end) over (partition by sk_task order by ts_action ROWS UNBOUNDED PRECEDING)
 		as sk_first_realized_date,
	min(case when action_type = 'RESOLVE' then sk_action_date else null end) over (partition by sk_task order by ts_action ROWS UNBOUNDED PRECEDING)
 		as sk_first_resolved_date,
	row_number() over(PARTITION BY sk_task ORDER BY ts_action) as rn,
    action_type,
    sk_assignee
 FROM crm_20211103.fact_lead_task_actions flta
),
task_dates as (
select 
	tm.sk_task,
	tm.sk_lead,
	min(tm.sk_created_date) as sk_created_date,
	min(tm.sk_first_realized_date) as sk_first_realized_date,
	min(tm.sk_first_resolved_date) as sk_first_resolved_date
from task_metrics tm
group by 1,2
)
, first_assignee as (
select 
	sk_task,
	min(rn) as min_rn		
from task_metrics tm
where sk_assignee <> -1
group by 1
)
, first_resolver as (
select 
	sk_task,
	min(rn) as min_rn		
from task_metrics tm
where action_type = 'REALIZE' and sk_assignee <> -1
group by 1
)
select
	td.sk_task,
	td.sk_lead,
	coalesce(td.sk_first_realized_date, -1) + COALESCE(td.sk_first_resolved_date, -1) <> -2 as is_closed,
	coalesce(td.sk_created_date, -1) as sk_created_date,
	coalesce(td.sk_first_realized_date, -1) as sk_first_realized_date,
	coalesce(td.sk_first_resolved_date, -1) as sk_first_resolved_date,
	coalesce(tm.sk_assignee, -1) as sk_user_first_assignee,
	coalesce(tm_fr.sk_assignee, -1) as sk_user_first_resolver
from task_dates td
join first_assignee fa
	on td.sk_task = fa.sk_task
join task_metrics tm 
	on tm.sk_task = fa.sk_task
	and tm.rn = fa.min_rn
left join first_resolver fr
	on td.sk_task = fr.sk_task
left join task_metrics tm_fr
	on tm_fr.sk_task = fr.sk_task
	and tm_fr.rn = fr.min_rn