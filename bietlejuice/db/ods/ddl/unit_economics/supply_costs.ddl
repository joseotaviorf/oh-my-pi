drop table if exists unit_economics.supply_costs;

CREATE TABLE unit_economics.supply_costs (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_affiliate_campaigns numeric NULL,
	vl_owner_campaigns numeric NULL,
	vl_photos float8 NULL,
	vl_inside_sales float8 NULL,
	vl_affiliate_bonus numeric NULL
)