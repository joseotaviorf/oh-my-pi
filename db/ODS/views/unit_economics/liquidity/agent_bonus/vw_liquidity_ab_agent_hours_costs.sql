drop view if exists vw_liquidity_ab_agent_hours_costs;
create or replace view vw_liquidity_ab_agent_hours_costs as
with hour_costs as (
  select distinct
    cd."Month" as dre_date,
    sum(agent_commission.vl_agent_commission) over (partition by agent_commission.dt_cash_flow)
       +  cd."Value" as hours
  from vw_net_revenue_agent_commission_costs agent_commission
  join files.costs_dre cd
    on cd."Month" = date_trunc('month', agent_commission.dt_cash_flow) - interval '2 month'
  where cd."Category" = 'Agents Commission'
),
property_daily_status as  (
	select
		id as property_id,
		"date" as dt_status,
		status_history as status
	from imovel_status_full_history
	where status_history = 'publicado'
),
all_costs as (
    select
      pds.property_id,
      pds.dt_status,
      hc.dre_date as dt_cash_flow,
      hc.hours /
        date_part('days', hc.dre_date + interval '1 month' - interval '1 day') /
        (count(pds.property_id) over (partition by hc.dre_date))::double precision as vl_agent_hours
    from property_daily_status pds
    left join hour_costs hc
      on hc.dre_date = date_trunc('month', pds.dt_status) + interval '1 month'
)
select
  vbpc.sk_property,
  ac.property_id,
  ac.dt_cash_flow::date,
  case
    when sum(ac.vl_agent_hours) > 0
      then 0
    else sum(ac.vl_agent_hours)
  end as vl_agent_hours
from all_costs ac
join vw_base_property_costs vbpc
  on vbpc.property_id = ac.property_id
    and ac.dt_cash_flow between vbpc.min_version_time and vbpc.max_version_time
group by vbpc.sk_property, ac.property_id, ac.dt_cash_flow
;