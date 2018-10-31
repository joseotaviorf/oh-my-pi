drop table if exists unit_economics.net_revenue_revenues_brokerage_plus_mgmt_aux;

CREATE TABLE unit_economics.net_revenue_revenues_brokerage_plus_mgmt_aux (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	brokerage_plus_mgmt numeric(14,4) NULL,
	dt_cash_flow date NULL,
	flg_expected_management_fee int4 NULL,
	flg_expected_brokerage_fee int4 NULL
)