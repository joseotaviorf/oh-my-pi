drop view vw_supply_costs;
---
--- Returns vl_tenant_campaigns costs for each first version property
--- Cost: Aggregated Marketing Costs
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view vw_supply_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	vl_affiliate_campaigns,
	vl_owner_campaigns
from
	vw_supply_mkt_costs
