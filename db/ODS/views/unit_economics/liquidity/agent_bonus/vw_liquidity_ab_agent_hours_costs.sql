drop view if exists vw_liquidity_ab_agent_hours_costs;
create or replace view vw_liquidity_ab_agent_hours_costs as
with hour_costs as (
  select distinct
    cd."Month" as dre_date,
    (-1 * cd."Value") -
        sum(agent_commission.vl_agent_commission) over (partition by agent_commission.dt_cash_flow) as hours
  from vw_net_revenue_agent_commission_costs agent_commission
  join files.costs_dre cd
    on cd."Month" = date_trunc('month', agent_commission.dt_cash_flow)
  where cd."Category" = 'Agents Commission'
),
filtered_visits as (
    select
      id as visit_id,
      imovel_id as property_id,
      data as dt
    from booking
    where tipo = 'Visita'
        and status = 'Realizado'
),
costs as (
    select
      fv.property_id,
      fv.dt,
      hc.dre_date as dt_cash_flow,
      hc.hours / (count(fv.property_id) over (partition by hc.dre_date))::double precision as vl_agent_hours
    from filtered_visits fv
    left join hour_costs hc
      on hc.dre_date = date_trunc('month', fv.dt)
),
-- In Jan-2016 there was no FUP; using 'Marcado' as visit confirmed
old_visists as (
    select
      id as visit_id,
      imovel_id as property_id,
      "data" as dt
    from booking
    where tipo = 'Visita'
        and status = 'Marcado'
        and date_trunc('month', "data") = '2016-01-01'
),
old_costs as (
    select
      ov.property_id,
      ov.dt,
      hc.dre_date as dt_cash_flow,
      hc.hours / (count(ov.property_id) over (partition by hc.dre_date))::double precision as vl_agent_hours
    from old_visists ov
    left join hour_costs hc
      on hc.dre_date = date_trunc('month', ov.dt)
),
all_costs as (
    select
        property_id,
        dt,
        dt_cash_flow,
        vl_agent_hours
    from costs

    union all

    select
        property_id,
        dt,
        dt_cash_flow,
        vl_agent_hours
    from old_costs
)
select
  vbpc.sk_property,
  ac.property_id,
  ac.dt_cash_flow::date,
  sum(ac.vl_agent_hours) as vl_agent_hours
from all_costs ac
join vw_base_property_costs vbpc
  on vbpc.property_id = ac.property_id
    and ac.dt between vbpc.min_version_time and vbpc.max_version_time
group by vbpc.sk_property, ac.property_id, ac.dt_cash_flow
;