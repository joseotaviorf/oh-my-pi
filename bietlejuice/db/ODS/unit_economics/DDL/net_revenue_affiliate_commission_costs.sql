drop table if exists unit_economics.net_revenue_affiliate_commission_costs;

CREATE TABLE unit_economics.net_revenue_affiliate_commission_costs (
	sk_property int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_affiliate_commission numeric(14,4) NULL,
	flg_expected_affiliate_commission int4 NULL
)