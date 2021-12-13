-- Table with supply daily costs by city_group

with
total_cost_daily as (
select
	dd.date,
	dd.week_start,
	dd.month_start,
	case when mdc.city_group = '' then 'Not Mapped' else mdc.city_group end as city_group,
	sum(mdc.cost) as costs_daily
from datalake_marketing_costs_prod.daily_costs mdc
join dim_date dd
  on mdc.id_date = dd.sk_date
where mdc.funnel_side = 'supply'
group by 1, 2, 3, 4
)
select
	*,
	sum(costs_daily) over(partition by week_start, city_group) as costs_weekly,
	sum(costs_daily) over(partition by month_start, city_group) as costs_monthly
from total_cost_daily