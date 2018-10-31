drop view if exists unit_economics.vw_liquidity_ab_agent_hours_costs;
create or replace view unit_economics.vw_liquidity_ab_agent_hours_costs as
with hour_costs as (
  select distinct
    cd.dre_date,
    sum(agent_commission.vl_agent_commission) over (partition by agent_commission.dt_cash_flow)
       +  cd.dre_value as hours
  from unit_economics.vw_net_revenue_agent_commission_costs agent_commission
  join unit_economics.vw_base_dre_costs cd
    on cd.dre_date = (date_trunc('month', agent_commission.dt_cash_flow) - interval '2 month')::date
  where cd.dre_category = 'Agents Commission'
),
filtered_daily_status as  (
	select
		base.sk_house_listing,
		id as property_id,
		"date" as dt_status,
		row_number()
			over (partition by isfh.id, base."version" order by isfh.id, isfh."date") as rn
	from
		imovel_status_full_history isfh
	left join
		unit_economics.vw_base_property_costs base
		on base.property_id = isfh.id
		where base.min_version_time <= isfh."date"
		and base.max_version_time > isfh."date"
	and status_history = 'publicado'
),
property_daily_status as  (
	select
		sk_house_listing,
		property_id,
		dt_status
	from
		filtered_daily_status
	where
		rn <= 365
),
all_costs as (
    select
      pds.sk_house_listing,
      pds.property_id,
      pds.dt_status,
      hc.dre_date as dt_cash_flow,
      hc.hours /
        date_part('days', hc.dre_date + interval '1 month' - interval '1 day') /
        (count(pds.property_id) over (partition by hc.dre_date))::double precision as vl_agent_hours
    from property_daily_status pds
    left join hour_costs hc
      on hc.dre_date = (date_trunc('month', pds.dt_status) + interval '1 month')::date
)
select
  ac.sk_house_listing,
  ac.property_id,
  ac.dt_cash_flow::date,
  case
    when sum(ac.vl_agent_hours) > 0
      then 0
    else sum(ac.vl_agent_hours)
  end as vl_agent_hours
from all_costs ac
join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = ac.property_id
    and ac.dt_cash_flow between vbpc.min_version_time and vbpc.max_version_time
group by ac.sk_house_listing, ac.property_id, ac.dt_cash_flow
;
