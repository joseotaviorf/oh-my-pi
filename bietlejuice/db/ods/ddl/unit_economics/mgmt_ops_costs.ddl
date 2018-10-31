DROP table if exists unit_economics.mgmt_ops_costs;

CREATE TABLE unit_economics.mgmt_ops_costs (
	sk_house_listing int8 NULL,
	property_id int8 NULL,
	dt_cash_flow date NULL,
	vl_bo_offboarding numeric(14,4) NULL,
	vl_bo_onboarding numeric(14,4) NULL,
	vl_bo_ongoing numeric(14,4) NULL,
	vl_collection numeric(14,4) NULL,
	vl_cs_post_sale numeric(14,4) NULL,
	vl_inspections numeric(14,4) NULL,
	flg_expected_bo_offboarding int4 NULL,
	flg_expected_bo_onboarding int4 NULL,
	flg_expected_bo_ongoing int4 NULL,
	flg_expected_collection int4 NULL,
	flg_expected_cs_post_sale int4 NULL,
	flg_expected_inspection int4 NULL
)