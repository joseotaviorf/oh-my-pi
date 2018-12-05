drop table if exists unit_economics.mgmt_ops_collection_costs;

CREATE TABLE unit_economics.mgmt_ops_collection_costs (
	sk_house_listing int8 NULL,
	property_id int4 NULL,
	dt_cash_flow date NULL,
	vl_collection float8 NULL,
	flg_expected_collection int4 NULL
)