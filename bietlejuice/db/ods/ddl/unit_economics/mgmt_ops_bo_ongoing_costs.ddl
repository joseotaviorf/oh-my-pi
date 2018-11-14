drop table if exists unit_economics.mgmt_ops_bo_ongoing_costs;

CREATE TABLE unit_economics.mgmt_ops_bo_ongoing_costs (
	sk_house_listing int8 NULL,
	property_id int4 NULL,
	dt_cash_flow date NULL,
	flg_expected_bo_ongoing int4 NULL,
	vl_bo_ongoing float8 NULL
)