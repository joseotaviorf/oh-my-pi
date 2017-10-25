drop view vw_fact_property_economics;
---
--- Returns the final view for Unit Economics
--- Cost: All costs grouped by versioned property / cash flow date
--- Cash Flow Date: Date of Payment
--- Placeholders with random int will be kept while developing the remainder values
---
create or replace view vw_fact_property_economics as
select
	sk_property,
	property_id,
	sk_cash_flow_date,
	-sum(vl_owner_campaigns) as vl_owner_campaigns,
	-sum(vl_affiliate_campaigns) as vl_affiliate_campaigns,
	-sum(vl_inside_sales) as vl_inside_sales,
	-sum(vl_photos) as vl_photos,
	(-1*cast(random()*10000 as int))::double precision as vl_affiliate_bonus,
	(-1*cast(random()*10000 as int))::double precision as vl_lockbox,
	-sum(vl_tenant_campaigns) as vl_tenant_campaigns,
	(-1*cast(random()*10000 as int))::double precision as vl_cs_pre_sale,
	(-1*cast(random()*10000 as int))::double precision as vl_field_ops,
	(-1*cast(random()*10000 as int))::double precision as vl_bo_pre_sale,
	(-1*cast(random()*10000 as int))::double precision as vl_agent_hours,
	(-1*cast(random()*10000 as int))::double precision as vl_pis_cofins,
	(-1*cast(random()*10000 as int))::double precision as vl_affiliate_commision,
	(-1*cast(random()*10000 as int))::double precision as vl_agent_commision,
	(-1*cast(random()*10000 as int))::double precision as vl_delay_fine,
	(-1*cast(random()*10000 as int))::double precision as vl_termination_fine,
	(-1*cast(random()*10000 as int))::double precision as vl_brokerage_fee,
	(-1*cast(random()*10000 as int))::double precision as vl_management_fee,
	(-1*cast(random()*10000 as int))::double precision as vl_cs_post_sale,
	(-1*cast(random()*10000 as int))::double precision as vl_collections,
	(-1*cast(random()*10000 as int))::double precision as vl_bo_onboarding,
	(-1*cast(random()*10000 as int))::double precision as vl_bo_ongoing,
	(-1*cast(random()*10000 as int))::double precision as vl_bo_offboarding,
	(-1*cast(random()*10000 as int))::double precision as vl_insurance_fee
from
(
	select
		sk_property,
		property_id,
		coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
		0 as vl_owner_campaigns,
		0 as vl_affiliate_campaigns,
		0 as vl_inside_sales,
		0 as vl_photos,
		0 as vl_affiliate_bonus,
		0 as vl_lockbox,
		vl_tenant_campaigns,
		0 as vl_cs_pre_sale,
		0 as vl_field_ops,
		0 as vl_bo_pre_sale,
		0 as vl_agent_hours,
		0 as vl_pis_cofins,
		0 as vl_affiliate_commision,
		0 as vl_agent_commision,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		0 as vl_brokerage_fee,
		0 as vl_management_fee,
		0 as vl_cs_post_sale,
		0 as vl_collections,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_bo_offboarding,
		0 as vl_insurance_fee
	from
		vw_liquidity_costs
	union all
	select
		sk_property,
		property_id,
		coalesce(replace(dt_cash_flow::varchar, '-', '')::integer, -1) as sk_cash_flow_date,
		vl_owner_campaigns,
		vl_affiliate_campaigns,
		vl_inside_sales as vl_inside_sales,
		vl_photos as vl_photos,
		0 as vl_affiliate_bonus,
		0 as vl_lockbox,
		0 as vl_tenant_campaigns,
		0 as vl_cs_pre_sale,
		0 as vl_field_ops,
		0 as vl_bo_pre_sale,
		0 as vl_agent_hours,
		0 as vl_pis_cofins,
		0 as vl_affiliate_commision,
		0 as vl_agent_commision,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		0 as vl_brokerage_fee,
		0 as vl_management_fee,
		0 as vl_cs_post_sale,
		0 as vl_collections,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_bo_offboarding,
		0 as vl_insurance_fee
	from
		vw_supply_costs
) tbl
group by sk_property, property_id, sk_cash_flow_date