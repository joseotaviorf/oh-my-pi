drop view vw_net_revenue_costs;
---
--- Returns net revenue costs and fees for each first version property
--- Cost: Commission and Taxes
--- Revenue: Brokerage and Management Fees
--- Cash Flow Date: Date of Payment
---
create or replace view vw_net_revenue_costs as
select
    coalesce(vnrcc.sk_property, vnrr.sk_property, vnrt.sk_property) as sk_property,
	coalesce(vnrcc.property_id, vnrr.property_id, vnrt.property_id) as property_id,
	coalesce(vnrcc.dt_cash_flow, vnrr.dt_cash_flow, vnrt.dt_cash_flow) as dt_cash_flow,
    coalesce(vl_affiliate_commission, 0) as vl_affiliate_commission,
	coalesce(vl_management_fee, 0) as vl_management_fee,
	coalesce(vl_brokerage_fee, 0) as vl_brokerage_fee,
	coalesce(vnrcc.vl_agent_commission, 0) as vl_agent_commission,
	coalesce(vnrt.vl_st_iss, 0) as vl_st_iss,
	coalesce(vnrt.vl_st_pis_cofins, 0) as vl_st_pis_cofins,
	coalesce(vnrt.vl_delay_fine, 0) as vl_delay_fine
from
    vw_net_revenue_commission_costs vnrcc
full outer join
    vw_net_revenue_revenues vnrr
    on vnrcc.sk_property = vnrr.sk_property
	and vnrcc.dt_cash_flow = vnrr.dt_cash_flow
full outer join
    vw_net_revenue_taxes vnrt
    on vnrcc.sk_property = vnrt.sk_property
	and vnrcc.dt_cash_flow = vnrt.dt_cash_flow
;
