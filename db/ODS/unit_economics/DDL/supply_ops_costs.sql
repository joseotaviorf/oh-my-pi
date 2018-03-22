drop table if exists unit_economics.supply_ops_costs;

CREATE TABLE unit_economics.supply_ops_costs (
	sk_property int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_photos float8 NULL,
	vl_inside_sales float8 NULL
)