drop view if exists unit_economics.vw_liquidity_ops_costs;
create or replace view unit_economics.vw_liquidity_ops_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	sum(vl_bo_pre_sale) as vl_bo_pre_sale,
	sum(vl_cs_pre_sale) as vl_cs_pre_sale,
	sum(vl_field_ops) as vl_field_ops
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_bo_pre_sale,
		0 as vl_cs_pre_sale,
		0 as vl_field_ops
	from
		unit_economics.vw_liquidity_ops_bo_pre_sale_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_pre_sale,
		vl_cs_pre_sale,
		0 as vl_field_ops
	from
		unit_economics.vw_liquidity_ops_cs_pre_sale_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_bo_pre_sale,
		0 as vl_cs_pre_sale,
		vl_field_ops
	from
		unit_economics.vw_liquidity_ops_field_ops_costs
) tbl
group by sk_property, property_id, dt_cash_flow
;