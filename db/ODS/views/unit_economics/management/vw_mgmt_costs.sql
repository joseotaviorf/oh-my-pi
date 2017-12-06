drop view if exists unit_economics.vw_mgmt_costs;
create or replace view unit_economics.vw_mgmt_costs as
select
  coalesce(ops.sk_property, ins.sk_property) as sk_property,
  coalesce(ops.property_id, ins.property_id) as property_id,
  coalesce(ops.dt_cash_flow, ins.dt_cash_flow) as dt_cash_flow,
  coalesce(ops.vl_bo_offboarding, 0) as vl_bo_offboarding,
  coalesce(ops.vl_bo_onboarding, 0) as vl_bo_onboarding,
  coalesce(ops.vl_bo_ongoing, 0) as vl_bo_ongoing,
  coalesce(ops.vl_collection, 0) as vl_collection,
  coalesce(ops.vl_cs_post_sale, 0) as vl_cs_post_sale,
  coalesce(ins.vl_insurance_fee, 0) as vl_insurance_fee,
  coalesce(ins.flg_expected, 0) as flg_expected_insurance_fee
from
	unit_economics.vw_mgmt_ops_costs ops
full outer join
	unit_economics.vw_mgmt_insurance_fee ins
	on ins.sk_property = ops.sk_property
     and ins.dt_cash_flow = ops.dt_cash_flow
;