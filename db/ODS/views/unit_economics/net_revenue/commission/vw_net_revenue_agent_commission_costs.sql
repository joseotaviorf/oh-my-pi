drop view if exists vw_net_revenue_agent_commission_costs;
create or replace view vw_net_revenue_agent_commission_costs as
with agents as (
  select distinct
    comm.*,
    cont.*,
    c.imovel_id,
    c."dataAssinado"
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
),
-- Agents Commission spreadsheet doesn't contain contracts before Feb-2016
all_contracts as (
  select
    c.imovel_id as property_id,
    -- '0.5' is the commission average of Jan-2016
    c."valorAluguel" * 0.5 as vl_agent_commission,
    date_trunc('month', "dataAssinado") as dt
  from contract c
  where date_trunc('month', "dataAssinado") = '2016-01-01'
    and tipo = 'FullService'

  union

  select
    property_id,
    vl_agent_commission,
    dt
  from filtered_properties
),
updated_dates as (
  select
    property_id,
    vl_agent_commission,
    dt + interval '2 month' as dt
  from all_contracts
)
select
  vbpc.sk_property,
  ud.property_id,
  make_date(extract(year from ud.dt)::int, extract(month from ud.dt)::int, 7) as dt_cash_flow,
  ud.vl_agent_commission
from updated_dates ud
join vw_base_property_costs vbpc
  on vbpc.property_id = ud.property_id
    and ud.dt between vbpc.min_version_time and vbpc.max_version_time
;