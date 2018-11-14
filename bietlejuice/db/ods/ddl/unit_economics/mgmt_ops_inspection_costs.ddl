drop table if exists unit_economics.mgmt_ops_inspection_costs;

CREATE TABLE unit_economics.mgmt_ops_inspection_costs (
	sk_house_listing int8 NULL,
	property_id int4 NULL,
	dt_cash_flow date NULL,
	vl_inspections float8 NULL,
	flg_expected_inspection int4 NULL
)