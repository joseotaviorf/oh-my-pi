drop table if exists unit_economics.supply_ops_photos_costs;

CREATE TABLE unit_economics.supply_ops_photos_costs (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_photos float8 NULL
)