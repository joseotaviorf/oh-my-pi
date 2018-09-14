drop table unit_economics.liquidity_mkt_tenant_campaigns_costs;

create table unit_economics.liquidity_mkt_tenant_campaigns_costs (
	sk_property bigint,
	property_id bigint,
	dt_cash_flow date,
	criteo_cost decimal(14,4),
	google_cost decimal(14,4),
	facebook_cost decimal(14,4),
	rtbhouse_cost decimal(14,4),
	classifieds_cost decimal(14,4),
	vl_tenant_campaigns decimal(14,4)
)