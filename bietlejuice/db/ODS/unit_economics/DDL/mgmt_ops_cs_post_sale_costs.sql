drop table if exists unit_economics.mgmt_ops_cs_post_sale_costs;

CREATE TABLE unit_economics.mgmt_ops_cs_post_sale_costs (
	sk_property int8 NULL,
	property_id int4 NULL,
	dt_cash_flow date NULL,
	vl_cs_post_sale float8 NULL,
	flg_expected_cs_post_sale int4 NULL
)