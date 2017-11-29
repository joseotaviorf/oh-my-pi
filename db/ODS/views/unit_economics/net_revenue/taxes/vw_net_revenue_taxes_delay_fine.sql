drop view if exists unit_economics.vw_net_revenue_taxes_delay_fine;
create or replace view unit_economics.vw_net_revenue_taxes_delay_fine as
with fines as (
  select
	inf.fine,
	inf.paid_date::date as dt,
	c.property_id as property_id
  from invoice_fines inf
  join unit_economics.vw_base_contract_costs c
    on inf.contract_id = c.id
)
select
  vbpc.sk_property,
  f.property_id,
  f.fine as vl_delay_fine,
  f.dt as dt_cash_flow
from fines f
join unit_economics.vw_base_property_costs vbpc
  on vbpc.property_id = f.property_id
    and f.dt between vbpc.min_version_time and vbpc.max_version_time
;