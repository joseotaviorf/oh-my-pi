--drop view if exists vw_net_revenue_agent_commission_costs;
--create or replace view vw_net_revenue_agent_commission_costs as
select dt_cash_flow, sum(vl_agent_commission) from (
--select count(distinct property_id) from (
with agents as (
  select distinct
    comm.*,
    cont.*,
    c.imovel_id
  from files.finance_agents_contract cont
  join files.finance_agents_commission comm
    on cont.agent_name = comm.agent_name
       and date_trunc('month', cont.signature_date) = comm.dt
  left join contract c
    on c.id = cont.contract_id
  where cont.status = 'Ativo'
),
filtered_properties as (
  select
    dt,
    coalesce(892700000 + property_id, imovel_id) as property_id,
    sum(percentage * rent) as vl_agent_commission
  from agents
  group by dt, property_id, contract_id, imovel_id
)
select
  vbpc.sk_property,
  fp.property_id,
  make_date(extract(year from fp.dt )::int, extract(month from fp.dt )::int, 7) as dt_cash_flow,
  fp.vl_agent_commission
from filtered_properties fp
join vw_base_property_costs vbpc
  on vbpc.property_id = fp.property_id
    and fp.dt between vbpc.min_version_time and vbpc.max_version_time
)a
group by 1
order by 1
;

select distinct dt, percentage
from files.finance_agents_commission
order by dt desc
;