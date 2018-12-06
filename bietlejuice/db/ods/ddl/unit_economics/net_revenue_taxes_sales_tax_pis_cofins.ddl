drop table if exists unit_economics.net_revenue_taxes_sales_tax_pis_cofins;

CREATE TABLE unit_economics.net_revenue_taxes_sales_tax_pis_cofins (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	vl_st_pis_cofins numeric(14,4) NULL,
	dt_cash_flow date NULL,
	flg_expected_sales_tax_pis_cofins int4 NULL
)