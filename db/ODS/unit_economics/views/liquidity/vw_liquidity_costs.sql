drop view if exists unit_economics.vw_liquidity_costs;
---
--- Returns vl_tenant_campaigns costs for each first version property
--- Cost: Aggregated Marketing Costs
--- Cash Flow Date: Date of Payment ( 1 month after invoice )
---
create or replace view unit_economics.vw_liquidity_costs as
select
	sk_property,
	property_id,
	date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
	sum(vl_tenant_campaigns)::decimal(14,4) as vl_tenant_campaigns,
	sum(vl_bo_pre_sale) as vl_bo_pre_sale,
	sum(vl_cs_pre_sale) as vl_cs_pre_sale,
	sum(vl_field_ops) as vl_field_ops,
	sum(vl_agent_hours) as vl_agent_hours,
	sum(vl_lockbox) as vl_lockbox
from
	(
		select
			sk_property,
			property_id,
			dt_cash_flow,
			vl_tenant_campaigns,
			0 as vl_bo_pre_sale,
			0 as vl_cs_pre_sale,
			0 as vl_field_ops,
			0 as vl_agent_hours,
			0 as vl_lockbox
		from
			unit_economics.vw_liquidity_mkt_costs
		union all
		select
			sk_property,
			property_id,
			dt_cash_flow,
			0 as vl_tenant_campaigns,
			0 as vl_bo_pre_sale,
			0 as vl_cs_pre_sale,
			0 as vl_field_ops,
			vl_agent_hours,
			0 as vl_lockbox
		from
			unit_economics.vw_liquidity_ab_agent_hours_costs
		union all
		select
			sk_property,
			property_id,
			dt_cash_flow,
			0 as vl_tenant_campaigns,
			vl_bo_pre_sale,
			vl_cs_pre_sale,
			vl_field_ops,
			0 as vl_agent_hours,
			0 as vl_lockbox
		from
			unit_economics.vw_liquidity_ops_costs
		union all
		select
			sk_property,
			property_id,
			dt_cash_flow,
			0 as vl_tenant_campaigns,
			0 as vl_bo_pre_sale,
			0 as vl_cs_pre_sale,
			0 as vl_field_ops,
			0 as vl_agent_hours,
			vl_lockbox
		from
			unit_economics.vw_liquidity_lockbox_costs
	) tbl
group by sk_property, property_id, dt_cash_flow
;