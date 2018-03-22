drop view if exists unit_economics.vw_net_revenue_taxes_sales_tax_iss;
create or replace view unit_economics.vw_net_revenue_taxes_sales_tax_iss as
with iss as (
  select
    sk_property,
    property_id,
    0.05 * brokerage_plus_mgmt as vl_st_iss,
    dt_cash_flow + interval '1 month' as dt_cash_flow
  from unit_economics.net_revenue_revenues_brokerage_plus_mgmt_aux
)
select
  sk_property,
  property_id,
  vl_st_iss,
  make_date(extract(year from dt_cash_flow)::int, extract(month from dt_cash_flow)::int, 25) as dt_cash_flow,
  1 as flg_expected_sales_tax_iss
from iss
;