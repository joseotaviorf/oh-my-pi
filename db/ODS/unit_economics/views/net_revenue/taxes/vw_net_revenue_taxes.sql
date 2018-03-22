drop view if exists unit_economics.vw_net_revenue_taxes;
create or replace view unit_economics.vw_net_revenue_taxes as
select
	sk_property,
	property_id,
	date_trunc('month', dt_cash_flow)::date as dt_cash_flow,
	sum(vl_st_iss) as vl_st_iss,
	sum(vl_st_pis_cofins) as vl_st_pis_cofins,
	sum(vl_delay_fine) as vl_delay_fine,
	sum(flg_expected_sales_tax_iss) as flg_expected_sales_tax_iss,
	sum(flg_expected_sales_tax_pis_cofins) as flg_expected_sales_tax_pis_cofins,
	sum(flg_expected_delay_fine) as flg_expected_delay_fine
from
(
	select
		sk_property,
		property_id,
		dt_cash_flow,
		vl_st_iss,
		0 as vl_st_pis_cofins,
		0 as vl_delay_fine,
		flg_expected_sales_tax_iss,
		0 as flg_expected_sales_tax_pis_cofins,
		0 as flg_expected_delay_fine
	from
		unit_economics.net_revenue_taxes_sales_tax_iss
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_st_iss,
		vl_st_pis_cofins,
		0 as vl_delay_fine,
		0 as flg_expected_sales_tax_iss,
		flg_expected_sales_tax_pis_cofins,
		0 as flg_expected_delay_fine
	from
		unit_economics.net_revenue_taxes_sales_tax_pis_cofins
	union all
	select
		sk_property,
		property_id,
		dt_cash_flow,
		0 as vl_st_iss,
		0 as vl_st_pis_cofins,
		vl_delay_fine,
		0 as flg_expected_sales_tax_iss,
		0 as flg_expected_sales_tax_pis_cofins,
		flg_expected_delay_fine
	from
		unit_economics.net_revenue_taxes_delay_fine
) tbl
group by sk_property, property_id, dt_cash_flow
;