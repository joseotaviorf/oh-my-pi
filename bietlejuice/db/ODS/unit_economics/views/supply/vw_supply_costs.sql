drop view if exists unit_economics.vw_supply_costs;
---
--- Returns all supply costs
--- Cost: Aggregated Supply Costs
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view unit_economics.vw_supply_costs as
select
	coalesce(vsmc.sk_property, vsoc.sk_property, vsacc.sk_property) as sk_property,
	coalesce(vsmc.property_id, vsoc.property_id, vsacc.property_id) as property_id,
	coalesce(
    date_trunc('month', vsmc.dt_cash_flow)::date,
    date_trunc('month', vsoc.dt_cash_flow)::date,
    date_trunc('month', vsacc.dt_cash_flow)::date) as dt_cash_flow,
	coalesce(vsmc.vl_affiliate_campaigns, 0) as vl_affiliate_campaigns,
	coalesce(vsmc.vl_owner_campaigns, 0) as vl_owner_campaigns,
	coalesce(vsoc.vl_photos, 0) as vl_photos,
	coalesce(vsoc.vl_inside_sales, 0) as vl_inside_sales,
	coalesce(vsacc.vl_affiliate_bonus, 0) as vl_affiliate_bonus
from
	unit_economics.supply_mkt_costs vsmc
full outer join unit_economics.supply_ops_costs vsoc
  	on vsmc.sk_property = vsoc.sk_property
	and vsmc.dt_cash_flow = vsoc.dt_cash_flow
full outer join unit_economics.supply_affiliate_bonus_costs vsacc
	on vsacc.sk_property = coalesce(vsoc.sk_property, vsmc.sk_property)
	and vsacc.dt_cash_flow = coalesce(vsoc.dt_cash_flow, vsmc.dt_cash_flow)
;