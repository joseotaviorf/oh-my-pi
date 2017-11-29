drop view if exists unit_economics.vw_mgmt_ops_costs;
create or replace view unit_economics.vw_mgmt_ops_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	sum(vl_bo_offboarding) as vl_bo_offboarding,
	sum(vl_bo_onboarding) as vl_bo_onboarding,
	sum(vl_bo_ongoing) as vl_bo_ongoing,
	sum(vl_collection) as vl_collection,
	sum(vl_cs_post_sale) as vl_cs_post_sale
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale
	from
		unit_economics.vw_mgmt_ops_bo_offboarding_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale
	from
		unit_economics.vw_mgmt_ops_bo_onboarding_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		vl_bo_ongoing,
		0 as vl_collection,
		0 as vl_cs_post_sale
	from
		unit_economics.vw_mgmt_ops_bo_ongoing_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		vl_collection,
		0 as vl_cs_post_sale
	from
		unit_economics.vw_mgmt_ops_collection_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_offboarding,
		0 as vl_bo_onboarding,
		0 as vl_bo_ongoing,
		0 as vl_collection,
		vl_cs_post_sale
	from
		unit_economics.vw_mgmt_ops_cs_post_sale_costs
) tbl
group by sk_property, property_id, dt_cash_flow
;