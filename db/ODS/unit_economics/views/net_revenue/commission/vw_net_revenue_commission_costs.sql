drop view if exists unit_economics.vw_net_revenue_commission_costs;
---
--- Returns vl_affiliate_commission costs for each first version property
--- Cost: Affiliate Commission on rented properties
--- Cash Flow Date: Date of Payment
---
create or replace view unit_economics.vw_net_revenue_commission_costs as
select
    coalesce(affiliate.sk_property, agent.sk_property) as sk_property,
    coalesce(affiliate.property_id, agent.property_id) as property_id,
    coalesce(affiliate.dt_cash_flow, agent.dt_cash_flow) as dt_cash_flow,
    coalesce(affiliate.vl_affiliate_commission, 0) as vl_affiliate_commission,
    coalesce(agent.vl_agent_commission, 0) as vl_agent_commission,
    coalesce(affiliate.flg_expected_affiliate_commission, 0) as flg_expected_affiliate_commission,
    coalesce(agent.flg_expected_agent_commission, 0) as flg_expected_agent_commission
from
    unit_economics.net_revenue_affiliate_commission_costs affiliate
full outer join unit_economics.net_revenue_agent_commission_costs agent
  on affiliate.sk_property = agent.sk_property
     and affiliate.dt_cash_flow = agent.dt_cash_flow
;