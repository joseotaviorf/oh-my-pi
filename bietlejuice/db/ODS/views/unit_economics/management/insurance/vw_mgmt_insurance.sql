drop view if exists unit_economics.vw_mgmt_insurance;

create or replace view unit_economics.vw_mgmt_insurance as
select
	coalesce(i_fee.sk_property, i_pis.sk_property) as sk_property,
	coalesce(i_fee.property_id, i_pis.property_id) as property_id,
	coalesce(i_fee.dt_cash_flow, i_pis.dt_cash_flow) as dt_cash_flow,
	coalesce(i_fee.vl_insurance_fee, 0) as vl_insurance_fee,
	coalesce(i_fee.vl_default_fee, 0) as vl_default_fee,
	coalesce(i_pis.vl_st_pis_cofins, 0) as vl_st_pis_cofins,
	coalesce(i_fee.flg_expected, 0) as flg_expected_insurance_fee,
	coalesce(i_pis.flg_expected, 0) as flg_expected_sales_tax_pis_cofins
from
	unit_economics.mgmt_insurance_fee i_fee
full outer join
	unit_economics.mgmt_insurance_pis_cofins i_pis
	on i_fee.sk_property = i_pis.sk_property
	and i_fee.dt_cash_flow = i_pis.dt_cash_flow
;