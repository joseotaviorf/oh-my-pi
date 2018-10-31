drop table if exists unit_economics.mgmt_insurance;

CREATE TABLE unit_economics.mgmt_insurance (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_insurance_fee numeric(14,4) NULL,
	vl_default_fee numeric(14,4) NULL,
	vl_st_pis_cofins numeric(14,4) NULL,
	flg_expected_insurance_fee int4 NULL,
	flg_expected_sales_tax_pis_cofins int4 NULL
)