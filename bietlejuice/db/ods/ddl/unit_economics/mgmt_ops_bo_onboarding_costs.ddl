drop table if exists unit_economics.mgmt_ops_bo_onboarding_costs;

CREATE TABLE unit_economics.mgmt_ops_bo_onboarding_costs (
	sk_property int8 NULL,
	property_id int4 NULL,
	dt_cash_flow date NULL,
	flg_expected_bo_onboarding int4 NULL,
	vl_bo_onboarding float8 NULL
)