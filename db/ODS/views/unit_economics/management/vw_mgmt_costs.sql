drop view if exists vw_mgmt_costs;
create or replace view vw_mgmt_costs as
select
  ops.sk_property as sk_property,
  ops.property_id as property_id,
  ops.dt_cash_flow as dt_cash_flow,
  ops.vl_bo_offboarding,
  ops.vl_bo_onboarding,
  ops.vl_bo_ongoing,
  ops.vl_collections,
  ops.vl_cs_post_sale
from
	vw_mgmt_ops_costs ops
;