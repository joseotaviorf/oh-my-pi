drop table unit_economics.liquidity_lockbox_costs;

create table unit_economics.liquidity_lockbox_costs (
	sk_property bigint,
	property_id bigint,
	dt_cash_flow date,
	vl_lockbox decimal(14,4)
)