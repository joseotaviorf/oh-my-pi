DROP table if exists unit_economics.net_revenue_costs;

CREATE TABLE unit_economics.net_revenue_costs (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_affiliate_commission numeric(14,4) NULL,
	vl_management_fee numeric(14,4) NULL,
	vl_rent_value numeric(14,4) NULL,
	vl_brokerage_fee numeric(14,4) NULL,
	vl_agent_commission numeric(14,4) NULL,
	vl_st_iss numeric(14,4) NULL,
	vl_st_pis_cofins numeric(14,4) NULL,
	vl_delay_fine numeric(14,4) NULL,
	flg_expected_management_fee int4 NULL,
	flg_expected_brokerage_fee int4 NULL,
	flg_expected_affiliate_commission int4 NULL,
	flg_expected_agent_commission int4 NULL,
	flg_expected_sales_tax_iss int4 NULL,
	flg_expected_sales_tax_pis_cofins int4 NULL,
	flg_expected_delay_fine int4 NULL
)