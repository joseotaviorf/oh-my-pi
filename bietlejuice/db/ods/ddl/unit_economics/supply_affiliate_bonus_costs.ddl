drop table if exists unit_economics.supply_affiliate_bonus_costs;

CREATE TABLE unit_economics.supply_affiliate_bonus_costs (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_affiliate_bonus numeric(14,4) NULL
)