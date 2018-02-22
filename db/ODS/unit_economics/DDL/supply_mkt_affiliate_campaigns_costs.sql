drop table if exists unit_economics.supply_mkt_affiliate_campaigns_costs;

CREATE TABLE unit_economics.supply_mkt_affiliate_campaigns_costs (
	sk_property int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_affiliate_campaigns numeric(14,4) NULL
)