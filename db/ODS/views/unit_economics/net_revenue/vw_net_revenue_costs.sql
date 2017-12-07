drop view if exists unit_economics.vw_net_revenue_costs;
---
--- Returns net revenue costs and fees for each first version property
--- Cost: Commission and Taxes
--- Revenue: Brokerage and Management Fees
--- Cash Flow Date: Date of Payment
---
create or replace view unit_economics.vw_net_revenue_costs as
select
	sk_property,
	property_id,
	dt_cash_flow,
	sum(vl_affiliate_commission) as vl_affiliate_commission,
	sum(vl_management_fee) as vl_management_fee,
	sum(flg_expected_management_fee) as flg_expected_management_fee,
	sum(vl_brokerage_fee) as vl_brokerage_fee,
	sum(vl_agent_commission) as vl_agent_commission,
	sum(vl_st_iss) as vl_st_iss,
	sum(vl_st_pis_cofins) as vl_st_pis_cofins,
	sum(vl_delay_fine) as vl_delay_fine
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_affiliate_commission,
		0 as vl_management_fee,
		0 as flg_expected_management_fee,
		0 as vl_brokerage_fee,
		vl_agent_commission,
		0 as vl_st_iss,
		0 as vl_st_pis_cofins,
		0 as vl_delay_fine
	from
		unit_economics.vw_net_revenue_commission_costs
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_affiliate_commission,
		vl_management_fee,
		flg_expected_management_fee,
		vl_brokerage_fee,
		0 as vl_agent_commission,
		0 as vl_st_iss,
		0 as vl_st_pis_cofins,
		0 as vl_delay_fine
	from
		unit_economics.vw_net_revenue_revenues
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_affiliate_commission,
		0 as vl_management_fee,
		0 as flg_expected_management_fee,
		0 as vl_brokerage_fee,
		0 as vl_agent_commission,
		vl_st_iss,
		vl_st_pis_cofins,
		vl_delay_fine
	from
		unit_economics.vw_net_revenue_taxes
) tbl
group by sk_property, property_id, dt_cash_flow
;
