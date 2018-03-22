drop view if exists unit_economics.vw_mgmt_costs;
create or replace view unit_economics.vw_mgmt_costs as
select
  coalesce(ops.sk_property, ins.sk_property) as sk_property,
  coalesce(ops.property_id, ins.property_id) as property_id,
  coalesce(date_trunc('month', ops.dt_cash_flow)::date, date_trunc('month', ins.dt_cash_flow)::date) as dt_cash_flow,
  coalesce(ops.vl_bo_offboarding, 0) as vl_bo_offboarding,
  coalesce(ops.vl_bo_onboarding, 0) as vl_bo_onboarding,
  coalesce(ops.vl_bo_ongoing, 0) as vl_bo_ongoing,
  coalesce(ops.vl_collection, 0) as vl_collection,
  coalesce(ops.vl_cs_post_sale, 0) as vl_cs_post_sale,
  coalesce(ops.vl_inspections, 0) as vl_inspections,
  coalesce(ins.vl_default_fee, 0) as vl_default_fee,
  coalesce(ins.vl_insurance_fee, 0) as vl_insurance_fee,
  coalesce(ins.vl_st_pis_cofins, 0) as vl_st_pis_cofins,
  coalesce(ops.flg_expected_bo_offboarding, 0) as flg_expected_bo_offboarding,
  coalesce(ops.flg_expected_bo_onboarding, 0) as flg_expected_bo_onboarding,
  coalesce(ops.flg_expected_bo_ongoing, 0) as flg_expected_bo_ongoing,
  coalesce(ops.flg_expected_collection, 0) as flg_expected_collection,
  coalesce(ops.flg_expected_cs_post_sale, 0) as flg_expected_cs_post_sale,
  coalesce(ops.flg_expected_inspection, 0) as flg_expected_inspection,
  coalesce(ins.flg_expected_insurance_fee, 0) as flg_expected_insurance_fee,
  coalesce(ins.flg_expected_sales_tax_pis_cofins, 0) as flg_expected_sales_tax_pis_cofins
from
	unit_economics.mgmt_ops_costs ops
full outer join
	unit_economics.mgmt_insurance ins
	on ins.sk_property = ops.sk_property
     and ins.dt_cash_flow = ops.dt_cash_flow
;