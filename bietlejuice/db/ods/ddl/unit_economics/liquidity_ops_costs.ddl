drop table unit_economics.tbl_liquidity_ops_costs;

create table unit_economics.tbl_liquidity_ops_costs (
	sk_house_listing bigint,
	property_id bigint,
	dt_cash_flow date,
	vl_bo_pre_sale decimal(14,4),
	vl_cs_pre_sale decimal(14,4),
	vl_field_ops decimal(14,4)
)