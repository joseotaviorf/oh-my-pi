drop table if exists unit_economics.net_revenue_revenues;

CREATE TABLE unit_economics.net_revenue_revenues (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_management_fee numeric(14,4) NULL,
	vl_rent_value numeric(14,4) NULL,
	flg_expected_management_fee int4 NULL,
	flg_expected_brokerage_fee int4 NULL,
	vl_brokerage_fee numeric(14,4) NULL
)