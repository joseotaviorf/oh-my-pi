drop view if exists vw_fact_property_economics;
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
	sum(vl_inside_sales) as vl_inside_sales,
	sum(vl_photos) as vl_photos,
	-sum(vl_affiliate_bonus) as vl_affiliate_bonus,
	(-1*cast(random()*10000 as int))::double precision as vl_lockbox,
	-sum(vl_tenant_campaigns) as vl_tenant_campaigns,
	sum(vl_cs_pre_sale) as vl_cs_pre_sale,
	sum(vl_field_ops) as vl_field_ops,
	sum(vl_bo_pre_sale) as vl_bo_pre_sale,
	(-1*cast(random()*10000 as int))::double precision as vl_agent_hours,
	(-1*cast(random()*10000 as int))::double precision as vl_pis_cofins,
	-sum(vl_affiliate_commission) as vl_affiliate_commission,
	(-1*cast(random()*10000 as int))::double precision as vl_agent_commission,
	(-1*cast(random()*10000 as int))::double precision as vl_delay_fine,
	(-1*cast(random()*10000 as int))::double precision as vl_termination_fine,
	sum(vl_brokerage_fee) as vl_brokerage_fee,
	sum(vl_management_fee) as vl_management_fee,
	sum(vl_cs_post_sale) as vl_cs_post_sale,
	sum(vl_collection) as vl_collection,
	sum(vl_bo_onboarding) as vl_bo_onboarding,
	sum(vl_bo_onboarding) as vl_bo_ongoing,
	sum(vl_bo_offboarding) as vl_bo_offboarding,
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
		vl_cs_pre_sale as vl_cs_pre_sale,
		vl_field_ops as vl_field_ops,
		vl_bo_pre_sale as vl_bo_pre_sale,
		0 as vl_agent_hours,
		0 as vl_pis_cofins,
		0 as vl_affiliate_commission,
		0 as vl_agent_commission,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		0 as vl_brokerage_fee,
		0 as vl_management_fee,
		0 as vl_cs_post_sale,
		0 as vl_collection,
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
		vl_affiliate_bonus,
		0 as vl_lockbox,
		0 as vl_tenant_campaigns,
		0 as vl_cs_pre_sale,
		0 as vl_field_ops,
		0 as vl_bo_pre_sale,
		0 as vl_agent_hours,
		0 as vl_pis_cofins,
		0 as vl_affiliate_commission,
		0 as vl_agent_commission,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		0 as vl_brokerage_fee,
		0 as vl_management_fee,
		0 as vl_cs_post_sale,
		0 as vl_collection,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_bo_offboarding,
		0 as vl_insurance_fee
	from
		vw_supply_costs
	union all
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
		0 as vl_tenant_campaigns,
		0 as vl_cs_pre_sale,
		0 as vl_field_ops,
		0 as vl_bo_pre_sale,
		0 as vl_agent_hours,
		0 as vl_pis_cofins,
		0 as vl_affiliate_commission,
		0 as vl_agent_commission,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		0 as vl_brokerage_fee,
		0 as vl_management_fee,
		vl_cs_post_sale as vl_cs_post_sale,
		vl_collection as vl_collection,
		vl_bo_onboarding as vl_bo_onboarding,
		vl_bo_ongoing as vl_bo_ongoing,
		vl_bo_offboarding as vl_bo_offboarding,
		0 as vl_insurance_fee
	from
		vw_mgmt_costs
	union all
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
		0 as vl_tenant_campaigns,
		0 as vl_cs_pre_sale,
		0 as vl_field_ops,
		0 as vl_bo_pre_sale,
		0 as vl_agent_hours,
		0 as vl_pis_cofins,
		vl_affiliate_commission as vl_affiliate_commission,
		0 as vl_agent_commission,
		0 as vl_delay_fine,
		0 as vl_termination_fine,
		vl_brokerage_fee as vl_brokerage_fee,
		vl_management_fee as vl_management_fee,
		0 as vl_cs_post_sale,
		0 as vl_collection,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_bo_offboarding,
		0 as vl_insurance_fee
	from
		vw_net_revenue_costs
) tbl
group by sk_property, property_id, sk_cash_flow_date
;
