drop table unit_economics.tbl_liquidity_ops_bo_pre_sale_costs;

create table unit_economics.tbl_liquidity_ops_bo_pre_sale_costs (
	sk_house_listing bigint,
	property_id bigint,
	dt_cash_flow date,
	vl_bo_pre_sale decimal(14,4)
)