drop view if exists vw_net_revenue_taxes;
create or replace view vw_net_revenue_taxes as
select
  coalesce(iss.sk_property, pis_cofins.sk_property) as sk_property,
  coalesce(iss.property_id, pis_cofins.sk_property) as property_id,
  coalesce(iss.dt_cash_flow, pis_cofins.dt_cash_flow) as dt_cash_flow,
  coalesce(iss.vl_sales_tax_iss, 0) as vl_st_iss,
  coalesce(pis_cofins.vl_sales_tax_pis_cofins, 0) as vl_st_pis_cofins
from vw_net_revenue_taxes_sales_tax_iss iss
full outer join vw_net_revenue_taxes_sales_tax_pis_cofins pis_cofins
  on iss.sk_property = pis_cofins.sk_property
     and iss.dt_cash_flow = pis_cofins.dt_cash_flow
;