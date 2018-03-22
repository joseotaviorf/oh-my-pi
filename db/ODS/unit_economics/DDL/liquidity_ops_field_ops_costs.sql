drop table unit_economics.tbl_liquidity_ops_field_ops_costs;

create table unit_economics.tbl_liquidity_ops_field_ops_costs (
	sk_property bigint,
	property_id bigint,
	dt_cash_flow date,
	vl_field_ops decimal(14,4)
)