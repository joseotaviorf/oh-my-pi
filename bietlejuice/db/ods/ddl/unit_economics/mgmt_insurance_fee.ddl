drop table if exists unit_economics.mgmt_insurance_fee;

CREATE TABLE unit_economics.mgmt_insurance_fee (
	sk_property int8 NULL,
	property_id int8 NULL,
	contract_id int8 NULL,
	vl_insurance_fee numeric(14,4) NULL,
	vl_default_fee numeric(14,4) NULL,
	dt_cash_flow date NULL,
	flg_expected int4 NULL
)