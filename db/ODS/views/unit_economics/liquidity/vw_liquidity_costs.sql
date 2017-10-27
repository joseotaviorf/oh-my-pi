drop view vw_liquidity_costs;
---
--- Returns vl_tenant_campaigns costs for each first version property
--- Cost: Aggregated Marketing Costs
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view vw_liquidity_costs as
select
  coalesce(mkt.sk_property, ops.sk_property, agent_hours.sk_property) as sk_property,
  coalesce(mkt.property_id, ops.property_id, agent_hours.property_id) as property_id,
  coalesce(mkt.dt_cash_flow, ops.dt_cash_flow, agent_hours.dt_cash_flow) as dt_cash_flow,
  coalesce(mkt.vl_tenant_campaigns, 0)::decimal(14,4) as vl_tenant_campaigns,
  coalesce(ops.vl_bo_pre_sale, 0) as vl_bo_pre_sale,
  coalesce(ops.vl_cs_pre_sale, 0) as vl_cs_pre_sale,
  coalesce(ops.vl_field_ops, 0) as vl_field_ops,
  coalesce(agent_hours.vl_agent_hours, 0) as vl_agent_hours
from
	vw_liquidity_mkt_costs mkt
full outer join vw_liquidity_ops_costs ops
  on mkt.sk_property = ops.sk_property
     and mkt.dt_cash_flow = ops.dt_cash_flow
full outer join vw_liquidity_ab_agent_hours_costs agent_hours
  on mkt.sk_property = agent_hours.sk_property
     and mkt.dt_cash_flow = agent_hours.dt_cash_flow
;