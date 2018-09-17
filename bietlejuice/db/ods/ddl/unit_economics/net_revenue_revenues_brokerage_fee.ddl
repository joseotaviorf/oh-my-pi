drop table if exists unit_economics.net_revenue_revenues_brokerage_fee;

CREATE TABLE unit_economics.net_revenue_revenues_brokerage_fee (
	sk_property int8 NULL,
	property_id int8 NULL,
	vl_brokerage_fee numeric(14,4) NULL,
	vl_rent_value numeric(14,4) NULL,
	dt_cash_flow date NULL,
	flg_expected_brokerage_fee int4 NULL
)