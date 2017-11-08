drop view if exists vw_supply_ops_costs;
create or replace view vw_supply_ops_costs as
select
  coalesce(vsopc.sk_property, vsoisc.sk_property) as sk_property,
  coalesce(vsopc.sk_property, vsoisc.sk_property) as property_id,
  coalesce(vsopc.dt_cash_flow, vsoisc.dt_cash_flow) as dt_cash_flow,
  coalesce(vsopc.vl_photos, 0) as vl_photos,
  coalesce(vsoisc.vl_inside_sales, 0) as vl_inside_sales
from vw_supply_ops_photos_costs vsopc
full outer join vw_supply_ops_inside_sales_costs vsoisc
  on vsoisc.sk_property = vsopc.sk_property
     and vsoisc.dt_cash_flow = vsopc.dt_cash_flow
;