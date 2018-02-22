drop table unit_economics.liquidity_costs;

create table unit_economics.liquidity_costs (
	sk_property bigint,
	property_id bigint,
	dt_cash_flow date,
	vl_tenant_campaigns decimal(14,4),
	vl_bo_pre_sale decimal(14,4),
	vl_cs_pre_sale decimal(14,4),
	vl_field_ops decimal(14,4),
	vl_agent_hours decimal(14,4),
	vl_lockbox decimal(14,4)
)