drop view if exists vw_liquidity_ops_costs;
create or replace view vw_liquidity_ops_costs as
select
  coalesce(bo_pre_sale.sk_property, pre_sale.sk_property, field_ops.sk_property) as sk_property,
  coalesce(bo_pre_sale.property_id, pre_sale.property_id, field_ops.property_id) as property_id,
  coalesce(bo_pre_sale.dt_cash_flow, pre_sale.dt_cash_flow, field_ops.dt_cash_flow) as dt_cash_flow,
  coalesce(bo_pre_sale.vl_bo_pre_sale, 0) as vl_bo_pre_sale,
  coalesce(pre_sale.vl_cs_pre_sale, 0) as vl_cs_pre_sale,
  coalesce(field_ops.vl_field_ops, 0) as vl_field_ops

from vw_liquidity_ops_bo_pre_sale_costs bo_pre_sale

full outer join vw_liquidity_ops_cs_pre_sale_costs pre_sale
  on pre_sale.sk_property = bo_pre_sale.sk_property
     and pre_sale.dt_cash_flow = bo_pre_sale.dt_cash_flow

full outer join vw_liquidity_ops_field_ops_costs field_ops
  on field_ops.sk_property = bo_pre_sale.sk_property
     and field_ops.dt_cash_flow = bo_pre_sale.dt_cash_flow

;
