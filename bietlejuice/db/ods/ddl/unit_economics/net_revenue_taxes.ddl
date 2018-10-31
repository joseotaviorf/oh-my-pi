drop table if exists unit_economics.net_revenue_taxes;

CREATE TABLE unit_economics.net_revenue_taxes (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_st_iss numeric(14,4) NULL,
	vl_st_pis_cofins numeric(14,4) NULL,
	vl_delay_fine numeric(14,4) NULL,
	flg_expected_sales_tax_iss int4 NULL,
	flg_expected_sales_tax_pis_cofins int4 NULL,
	flg_expected_delay_fine int4 NULL
)