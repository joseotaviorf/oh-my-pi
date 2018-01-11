drop view if exists unit_economics.vw_net_revenue_taxes_sales_tax_pis_cofins;
create or replace view unit_economics.vw_net_revenue_taxes_sales_tax_pis_cofins as
with pis_cofins as (
    select
        sk_property,
        property_id,
        0.0925 * brokerage_plus_mgmt as vl_st_pis_cofins,
        dt_cash_flow + interval '1 month' as dt_cash_flow
    from unit_economics.vw_net_revenue_revenues_brokerage_plus_mgmt_aux
)
select
  sk_property,
  property_id,
  vl_st_pis_cofins,
  make_date(extract(year from dt_cash_flow)::int, extract(month from dt_cash_flow)::int, 10) as dt_cash_flow,
  0 as flg_expected_sales_tax_pis_cofins
from pis_cofins
;
