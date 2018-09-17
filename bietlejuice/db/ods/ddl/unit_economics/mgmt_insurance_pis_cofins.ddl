drop table if exists unit_economics.mgmt_insurance_pis_cofins;

CREATE TABLE unit_economics.mgmt_insurance_pis_cofins (
	sk_property int8 NULL,
	property_id int8 NULL,
	contract_id int8 NULL,
	vl_st_pis_cofins numeric(14,4) NULL,
	dt_cash_flow date NULL,
	flg_expected int4 NULL
)