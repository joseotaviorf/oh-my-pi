drop table if exists unit_economics.net_revenue_taxes_sales_tax_iss;

CREATE TABLE unit_economics.net_revenue_taxes_sales_tax_iss (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	vl_st_iss numeric(14,4) NULL,
	dt_cash_flow date NULL,
	flg_expected_sales_tax_iss int4 NULL
)