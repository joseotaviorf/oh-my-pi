drop view vw_supply_costs;
---
--- Returns vl_tenant_campaigns costs for each first version property
--- Cost: Aggregated Marketing Costs
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view vw_supply_costs as
select
	coalesce(vsmc.sk_property, vsoc.sk_property) as sk_property,
	coalesce(vsmc.property_id, vsoc.property_id) as property_id,
	coalesce(vsmc.dt_cash_flow, vsoc.dt_cash_flow) as dt_cash_flow,
	coalesce(vsmc.vl_affiliate_campaigns, 0) as vl_affiliate_campaigns,
	coalesce(vsmc.vl_owner_campaigns, 0) as vl_owner_campaigns,
	coalesce(vsoc.vl_photos, 0) as vl_photos,
	coalesce(vsoc.vl_inside_sales, 0) as vl_inside_sales
from
	vw_supply_mkt_costs vsmc
full outer join vw_supply_ops_costs vsoc
  on vsmc.sk_property = vsoc.sk_property
     and vsmc.dt_cash_flow = vsoc.dt_cash_flow
;