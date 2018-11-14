drop table unit_economics.liquidity_ab_agent_hours_costs;

create table unit_economics.liquidity_ab_agent_hours_costs (
	sk_house_listing bigint,
	property_id bigint,
	dt_cash_flow date,
	vl_agent_hours decimal(14,4)
)