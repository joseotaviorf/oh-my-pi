drop table if exists unit_economics.mgmt_ops_bo_offboarding_costs;

CREATE TABLE unit_economics.mgmt_ops_bo_offboarding_costs (
	sk_property int8 NULL,
	property_id int4 NULL,
	dt_cash_flow date NULL,
	vl_bo_offboarding float8 NULL,
	flg_expected int4 NULL
)