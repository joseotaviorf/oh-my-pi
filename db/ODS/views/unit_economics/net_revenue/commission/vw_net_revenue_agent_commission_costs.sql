drop view if exists vw_net_revenue_agent_commission_costs;
create or replace view vw_net_revenue_agent_commission_costs as
with filtered_properties as (
  select
      comm.dt,
      coalesce(cont.property_id, c.imovel_id) as property_id,
      sum(comm.percentage * cont.rent) as vl_agent_commission
  from files.finance_agents_contract cont
  join files.finance_agents_commission comm
    on cont.agent_name = comm.agent_name
       and date_trunc('month', cont.signature_date) = comm.dt
  join contract c
    on c.id = cont.contract_id
  where cont.status = 'Ativo'
  group by comm.dt, cont.property_id, cont.contract_id, c.id, c.imovel_id
)
select
  vbpc.sk_property,
  fp.property_id,
  fp.dt as dt_cash_flow,
  fp.vl_agent_commission
from filtered_properties fp
join vw_base_property_costs vbpc
  on vbpc.property_id = fp.property_id
    and fp.dt between vbpc.min_version_time and vbpc.max_version_time
;