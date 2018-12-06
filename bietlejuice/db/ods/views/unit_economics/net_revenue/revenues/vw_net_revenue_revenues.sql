drop view if exists unit_economics.vw_net_revenue_revenues;
---
--- Returns
---     vl_management_fee
---     vl_brokerage_fee
--- for each versioned property
---
create or replace view unit_economics.vw_net_revenue_revenues as
select
	coalesce(b_fee.sk_house_listing, m_fee.sk_house_listing) as sk_house_listing,
	coalesce(b_fee.property_id, m_fee.property_id) as property_id,
	coalesce(date_trunc('month', b_fee.dt_cash_flow)::date, date_trunc('month', m_fee.dt_cash_flow)::date) as dt_cash_flow,
	coalesce(m_fee.vl_management_fee, 0) as vl_management_fee,
	coalesce(m_fee.vl_rent_value, b_fee.vl_rent_value) as vl_rent_value,
	coalesce(m_fee.flg_expected_management_fee, 0) as flg_expected_management_fee,
	coalesce(b_fee.flg_expected_brokerage_fee, 0) as flg_expected_brokerage_fee,
	coalesce(b_fee.vl_brokerage_fee, 0) as vl_brokerage_fee
from
	unit_economics.net_revenue_revenues_brokerage_fee b_fee
full outer join
	unit_economics.net_revenue_revenues_mgmt_fee m_fee
	on b_fee.sk_house_listing = m_fee.sk_house_listing
	and b_fee.dt_cash_flow = m_fee.dt_cash_flow
;
