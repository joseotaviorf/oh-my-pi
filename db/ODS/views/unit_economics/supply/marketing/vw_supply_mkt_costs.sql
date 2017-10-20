drop view vw_supply_mkt_costs;
---
--- Returns
---     vl_affiliate_campaigns
---     vl_owner_campaigns
---     sk_cash_flow_date
--- for each versioned property
---
create or replace view vw_supply_mkt_costs as
select
	coalesce(affiliate.sk_property, owner.sk_property) as sk_property,
	coalesce(affiliate.property_id, owner.property_id) as property_id,
	coalesce(affiliate.dt_cash_flow, owner.dt_cash_flow) as dt_cash_flow,
	coalesce(vl_affiliate_campaigns, 0) as vl_affiliate_campaigns,
	coalesce(vl_owner_campaigns, 0) as vl_owner_campaigns
from
	vw_supply_mkt_affiliate_campaigns_costs affiliate
full outer join
	vw_supply_mkt_owner_campaigns_costs owner
	on affiliate.sk_property = owner.sk_property
	and affiliate.dt_cash_flow = owner.dt_cash_flow