drop view vw_liquidity_costs;
---
--- Returns vl_tenant_campaigns costs for each first version property
--- Cost: Aggregated Marketing Costs
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view vw_liquidity_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	vl_tenant_campaigns
from
	vw_liquidity_mkt_costs
