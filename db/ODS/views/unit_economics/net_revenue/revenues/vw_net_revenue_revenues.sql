drop view vw_net_revenue_revenues;
---
--- Returns
---     vl_management_fee
---     vl_brokerage_fee
--- for each versioned property
---
create or replace view vw_net_revenue_revenues as
select
	coalesce(b_fee.sk_property, m_fee.sk_property) as sk_property,
	coalesce(b_fee.property_id, m_fee.property_id) as property_id,
	coalesce(b_fee.dt_cash_flow, m_fee.dt_cash_flow) as dt_cash_flow,
	coalesce(vl_management_fee, 0) as vl_management_fee,
	coalesce(vl_brokerage_fee, 0) as vl_brokerage_fee
from
	vw_net_revenue_revenues_brokerage_fee b_fee
full outer join
	vw_net_revenue_revenues_mgmt_fee m_fee
	on b_fee.sk_property = m_fee.sk_property
	and b_fee.dt_cash_flow = m_fee.dt_cash_flow
;
