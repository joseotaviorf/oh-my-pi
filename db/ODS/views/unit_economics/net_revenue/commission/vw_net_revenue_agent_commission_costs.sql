drop view if exists vw_net_revenue_agent_commission_costs;
create or replace view vw_net_revenue_agent_commission_costs as
with agents as (
  select distinct
    comm.dt,
    comm.percentage,
    cont.property_id as cont_property_id,
    cont.rent,
    cont.contract_id,
    c.property_id as c_property_id,
    c.signature_date
  from files.finance_agents_contract cont
  join files.finance_agents_commission comm
    on cont.agent_name = comm.agent_name
       and date_trunc('month', cont.signature_date) = comm.dt
  left join vw_base_contract_costs c
    on c.id = cont.contract_id
  where cont.status = 'Ativo'
),
filtered_properties as (
  select
    dt,
    coalesce(c_property_id, 892700000 + cont_property_id) as property_id,
    sum(percentage * rent) as vl_agent_commission
  from agents
  group by dt, c_property_id, contract_id, cont_property_id
),
-- Agents Commission spreadsheet doesn't contain contracts before Feb-2016
all_contracts as (
  select
    c.property_id,
    -- '0.5' is the commission average of Jan-2016
    c.rent_value * 0.5 as vl_agent_commission,
    date_trunc('month', signature_date) as dt
  from vw_base_contract_costs c
  where date_trunc('month', signature_date) = '2016-01-01'

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