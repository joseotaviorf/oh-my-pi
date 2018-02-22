drop table unit_economics.liquidity_mkt_costs;

create table unit_economics.liquidity_mkt_costs (
	sk_property bigint,
	property_id bigint,
	dt_cash_flow date,
	vl_tenant_campaigns decimal(14,4)
)