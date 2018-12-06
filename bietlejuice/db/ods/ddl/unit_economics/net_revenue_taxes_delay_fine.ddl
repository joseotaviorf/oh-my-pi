drop table if exists unit_economics.net_revenue_taxes_delay_fine;

CREATE TABLE unit_economics.net_revenue_taxes_delay_fine (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	vl_delay_fine numeric(14,4) NULL,
	dt_cash_flow date NULL,
	flg_expected_delay_fine int4 NULL
)